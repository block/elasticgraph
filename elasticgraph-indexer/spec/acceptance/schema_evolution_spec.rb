# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/indexer"
require "elastic_graph/schema_definition/rake_tasks"

module ElasticGraph
  RSpec.describe "Indexing schema evolution", :uses_datastore, :factories, :capture_logs, :in_temp_dir, :rake_task do
    let(:path_to_schema) { "config/schema.rb" }

    before do
      ::FileUtils.mkdir_p "config"
    end

    context "when the schema has evolved to gain a new field" do
      it "can ingest an event published before that field existed" do
        write_address_schema_def(json_schema_version: 1)
        dump_artifacts

        address_1_event = build_address_event_without_geolocation
        address_2_event = build_address_event_without_geolocation

        boot_indexer.processor.process([address_1_event], refresh_indices: true)

        write_address_schema_def(json_schema_version: 2, address_extras: "t.field 'geo_location', 'GeoLocation'")
        dump_artifacts

        indexer_with_geo_location = boot_indexer
        indexer_with_geo_location.processor.process([address_2_event], refresh_indices: true)

        expect(search_for_ids("addresses")).to contain_exactly(
          address_1_event.fetch("id"),
          address_2_event.fetch("id")
        )
      end

      def build_address_event_without_geolocation
        build_upsert_event(:address, __exclude_fields: [:geo_location]).tap do |event|
          # Verify that our `__exclude_fields` option worked correctly since the correctness of this test depends on it.
          expect(event.fetch("record").keys).to exclude("geo_location")
        end
      end
    end

    context "when the fields used for routing and index rollover have been renamed" do
      it "can ingest an event published before the renames" do
        write_widget_schema_def(
          json_schema_version: 1,
          widget_extras: <<~EOS,
            t.field "created_at", "DateTime!"
            t.field "name", "String"
          EOS
          widgets_index_config: <<~EOS
            i.rollover :yearly, "created_at"
            i.route_with "name"
          EOS
        )
        dump_artifacts

        write_widget_schema_def(
          json_schema_version: 2,
          widget_extras: <<~EOS,
            t.field "created_at2", "DateTime!", name_in_index: "created_at" do |f|
              f.renamed_from "created_at"
            end
            t.field "name2", "String", name_in_index: "name" do |f|
              f.renamed_from "name"
            end
          EOS
          widgets_index_config: <<~EOS
            i.rollover :yearly, "created_at2"
            i.route_with "name2"
          EOS
        )
        dump_artifacts

        v1_event = build_widget(json_schema_version: 1) do |widget|
          widget.slice("id", "name", "created_at")
        end

        v2_event = build_widget(json_schema_version: 2) do |widget|
          widget.slice("id").merge(
            "name2" => widget.fetch("name"),
            "created_at2" => widget.fetch("created_at")
          )
        end

        expect {
          boot_indexer.processor.process([v1_event, v2_event], refresh_indices: true)
        }.not_to raise_error
      end

      def build_widget(json_schema_version:)
        event = build_upsert_event(:widget, __json_schema_version: json_schema_version)
        event.merge("record" => (yield event.fetch("record")))
      end
    end

    context "when a schema has evolved to lose a new field and we are running on a new datastore cluster that doesn't have the removed field in its mapping" do
      it "can still ingest old schema version events that have the removed field" do
        write_address_schema_def(json_schema_version: 1, address_extras: "t.field 'deprecated', 'String'")
        dump_artifacts

        # Attempt to drop the field; ElasticGraph should give us an error due to it still existing in the old JSON schema version.
        write_address_schema_def(json_schema_version: 2)
        expect { dump_artifacts }.to abort_with a_string_including(
          "The `Address.deprecated` field (which existed in JSON schema version 1) no longer exists in the current schema definition."
        )

        # Try again after indicating the field has been deleted.
        write_address_schema_def(json_schema_version: 2, address_extras: "t.deleted_field 'deprecated'")
        dump_artifacts

        event = build_upsert_event(:address, id: "abc", deprecated: "foo", __json_schema_version: 1)
        expect(event.dig("record", "deprecated")).to eq("foo")

        boot_indexer.processor.process([event], refresh_indices: true)

        expect(get_address_payload("abc")).to include("id" => "abc").and exclude("deprecated")
      end

      def get_address_payload(id)
        search("addresses").find { |h| h.fetch("_id") == id }.fetch("_source")
      end
    end

    context "when a type referenced from a `nested` field is renamed as part of evolving the schema" do
      let(:existing_team_schema_def) do
        ::File.read(::File.join(CommonSpecHelpers::REPO_ROOT, "config", "schema", "teams.rb"))
      end

      it "can index events for either JSON schema version" do
        # Write v1 schema with a public `wins` JsonSafeLong field called `wins` in the index
        write_teams_schema_def(json_schema_version: 1) do |team_def|
          expect(team_def).to include('t.field "seasons_nested", "[TeamSeason!]!"')
          team_def
        end
        dump_artifacts

        # Write v2 schema with a public `wins` Int field with an alternate name in the index (to allow the type to change)
        write_teams_schema_def(json_schema_version: 2) do |team_def|
          safe_replace(team_def, "TeamSeason", "SeasonOfATeam").then do |updated|
            safe_replace(
              updated,
              'schema.object_type "SeasonOfATeam" do |t|',
              <<~EOS
                schema.object_type "SeasonOfATeam" do |t|
                  t.renamed_from "TeamSeason"
              EOS
            )
          end
        end
        dump_artifacts

        # The bug this test was written to cover relates to `__typename`, and was only triggered
        # when a nested field's type included `__typename` even though it's not required to be
        # included at that part of the JSON schema. So here we verify that the factory includes that.
        expect(build(:team_season)).to include(__typename: "TeamSeason")

        v1_event = build_upsert_event(:team, __json_schema_version: 1)
        v2_event = build_upsert_event(:team, __json_schema_version: 2)
          .then { |event| ::JSON.generate(event) }
          # Fix the event to align with the v2 schema, since `build_upsert_event` doesn't automatically
          # know that the `__typename` should be `SeasonOfATeam` instead of `TeamSeason`.
          .then { |json| json.gsub("TeamSeason", "SeasonOfATeam") }
          .then { |json| ::JSON.parse(json) }

        expect {
          boot_indexer.processor.process([v1_event, v2_event], refresh_indices: true)
        }.not_to raise_error
      end
    end

    context "when a field under a `nested` field uses `name_in_index` as part of evolving the schema" do
      let(:existing_team_schema_def) do
        ::File.read(::File.join(CommonSpecHelpers::REPO_ROOT, "config", "schema", "teams.rb"))
      end

      context "when `name_in_index` is added to an existing field to change the internal index field while keeping the same public field" do
        it "can index events for either JSON schema version" do
          # Write v1 schema with a public `wins` JsonSafeLong field called `wins` in the index
          write_teams_schema_def(json_schema_version: 1) do |team_def|
            safe_replace(
              team_def,
              't.field "wins", "Int", name_in_index: "win_count"',
              't.field "wins", "JsonSafeLong"'
            )
          end
          dump_artifacts

          # Write v2 schema with a public `wins` Int field with an alternate name in the index (to allow the type to change)
          write_teams_schema_def(json_schema_version: 2) do |team_def|
            expect(team_def).to include('t.field "wins", "Int", name_in_index: "win_count"')
            team_def
          end
          dump_artifacts

          v1_event = build_upsert_event(:team, __json_schema_version: 1)
          v2_event = build_upsert_event(:team, __json_schema_version: 2)

          expect {
            boot_indexer.processor.process([v1_event, v2_event], refresh_indices: true)
          }.not_to raise_error
        end
      end

      context "when a public field is renamed and `name_in_index` is used to make the new field keep reading and writing the existing index field" do
        it "can index events for either JSON schema version" do
          # Write a v1 schema with a `full_name` field that is called `name` in the index
          write_teams_schema_def(json_schema_version: 1) do |team_def|
            safe_replace(
              team_def,
              't.field "name", "String"',
              't.field "full_name", "String", name_in_index: "name"'
            )
          end
          dump_artifacts

          # Attempt to write a v2 schema with the `full_name` field renamed to `name` (while keeping the same field name in the index)
          # ElasticGraph should raise an error since it's not sure what to do with that field on old events.
          write_teams_schema_def(json_schema_version: 2) do |team_def|
            expect(team_def).to include 't.field "name", "String"'
            team_def
          end
          expect { dump_artifacts }.to abort_with a_string_including(
            "The `Player.full_name` field (which existed in JSON schema version 1) no longer exists in the current schema definition."
          )

          write_teams_schema_def(json_schema_version: 2) do |team_def|
            safe_replace(
              team_def,
              't.field "name", "String"',
              <<~EOS
                t.field "name", "String" do |f|
                  f.renamed_from "full_name"
                end
              EOS
            )
          end
          dump_artifacts

          v1_event = build_upsert_event(:team, __json_schema_version: 1)
          v1_event = ::JSON.parse(::JSON.generate(v1_event).gsub('"name":', '"full_name":'))
          v2_event = build_upsert_event(:team, __json_schema_version: 2)

          expect {
            boot_indexer.processor.process([v1_event, v2_event], refresh_indices: true)
          }.not_to raise_error
        end
      end

      context "when an embedded type that was in an old JSON schema has been dropped" do
        it "correctly ignores that type's data when ingesting old events" do
          write_teams_schema_def(json_schema_version: 1) do |team_def|
            # V1 has a `team_details: TeamDetails` field.
            expect(team_def).to include('schema.object_type "TeamDetails"', 't.field "details", "TeamDetails"')
            team_def
          end
          dump_artifacts

          # Attempt to write a v2 schema with the `TeamDetails` type and referencing field removed.
          # ElasticGraph should raise an error since it's not sure what to do with that field/type on old events.
          write_teams_schema_def(json_schema_version: 2) do |team_def|
            safe_replace(
              safe_replace(team_def, 't.field "details", "TeamDetails"', ""),
              /schema.object_type "TeamDetails".*?\bend\n/m,
              ""
            )
          end
          expect {
            dump_artifacts
          }.to abort_with a_string_including(
            "The `Team.details` field (which existed in JSON schema version 1) no longer exists in the current schema definition.",
            "The `TeamDetails` type (which existed in JSON schema version 1) no longer exists in the current schema definition."
          )

          write_teams_schema_def(json_schema_version: 2) do |team_def|
            safe_replace(
              safe_replace(team_def, 't.field "details", "TeamDetails"', 't.deleted_field "details"'),
              /schema.object_type "TeamDetails".*?\bend\n/m,
              'schema.deleted_type "TeamDetails"'
            )
          end
          dump_artifacts

          v1_event = build_upsert_event(:team, __json_schema_version: 1)

          expect {
            boot_indexer.processor.process([v1_event], refresh_indices: true)
          }.not_to raise_error
        end
      end

      context "when an indexed type that was in an old JSON schema has been dropped" do
        it "ignores an old event attempting to upsert that type" do
          write_address_schema_def(json_schema_version: 1, schema_extras: <<~EOS)
            schema.object_type "Team" do |t|
              t.field "id", "ID!"
              t.field "current_name", "String"
              t.field "league", "String"
              t.field "formed_on", "Date"
              t.index "teams" do |i|
                i.route_with "league"
                i.rollover :yearly, "formed_on"
              end
            end
          EOS
          dump_artifacts

          # Attempt to drop the `Team` indexed type--ElasticGraph should fail indicating it is still on the v1 schema.
          write_address_schema_def(json_schema_version: 2)
          expect {
            dump_artifacts
          }.to abort_with a_string_including(
            "The `Team` type (which existed in JSON schema version 1) no longer exists in the current schema definition."
          )

          write_address_schema_def(json_schema_version: 2, schema_extras: 'schema.deleted_type "Team"')
          dump_artifacts

          v1_event = build_upsert_event(:team, __json_schema_version: 1)
          boot_indexer.processor.process([v1_event], refresh_indices: true)

          expect(search_for_ids("teams")).to be_empty
        end
      end
    end

    def write_teams_schema_def(json_schema_version:)
      # Comment out some lines that lead to schema dump warnings (we don't want the warnings in the output).
      schema_def_contents = existing_team_schema_def.gsub(/^\s+t\.field schema\.state.schema_elements.count/, "#")
      schema_def_contents = yield schema_def_contents

      ::File.write(path_to_schema, <<~EOS)
        ElasticGraph.define_schema do |schema|
          schema.json_schema_version #{json_schema_version}

          # Money is referenced by the team schema but is defined in the widgets schema so we have duplicate it here.
          schema.object_type "Money" do |t|
            t.field "currency", "String!"
            t.field "amount_cents", "Int"
          end
        end

        #{schema_def_contents}
      EOS
    end

    def write_address_schema_def(json_schema_version:, address_extras: "", schema_extras: "")
      # This is a pared down schema definition of our normal test schema `Address` type.
      ::File.write(path_to_schema, <<~EOS)
        ElasticGraph.define_schema do |schema|
          schema.json_schema_version #{json_schema_version}

          schema.object_type "Address" do |t|
            t.field "id", "ID!"
            t.field "full_address", "String!"
            #{address_extras}
            t.index "addresses"
          end

          #{schema_extras}
        end
      EOS
    end

    def write_widget_schema_def(json_schema_version:, widget_extras: "", widgets_index_config: "")
      # This is a pared down schema definition of our normal test schema `Address` type.
      ::File.write(path_to_schema, <<~EOS)
        ElasticGraph.define_schema do |schema|
          schema.json_schema_version #{json_schema_version}

          schema.object_type "Widget" do |t|
            t.field "id", "ID!"
            #{widget_extras}
            t.index "widgets", number_of_shards: 10 do |i|
              #{widgets_index_config}
            end
          end
        end
      EOS
    end

    # Like `gsub` but also asserts that the expected pattern is in the string, so that we know that it actually replaced something.
    def safe_replace(string, pattern, replace_with)
      if pattern.is_a?(::String)
        expect(string).to include(pattern)
      else
        expect(string).to match(pattern)
      end

      string.gsub(pattern, replace_with)
    end

    def dump_artifacts
      run_rake "schema_artifacts:dump" do |output|
        SchemaDefinition::RakeTasks.new(
          schema_element_name_form: :snake_case,
          index_document_sizes: true,
          path_to_schema: path_to_schema,
          schema_artifacts_directory: "config/schema/artifacts",
          enforce_json_schema_version: true,
          output: output
        )
      end
    end

    def boot_indexer
      settings = CommonSpecHelpers.parsed_test_settings_yaml
      settings = Support::HashUtil.deep_merge(settings, {"schema_artifacts" => {"directory" => "config/schema/artifacts"}})

      Indexer.from_parsed_yaml(settings)
    end

    def search_for_ids(index_prefix)
      search(index_prefix).map { |h| h.fetch("_id") }
    end

    def search(index_prefix)
      main_datastore_client
        .msearch(body: [{index: "#{index_prefix}*"}, {}])
        .dig("responses", 0, "hits", "hits")
    end
  end
end
