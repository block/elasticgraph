# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/constants"
require "elastic_graph/json_ingestion/schema_definition/api_extension"
require "elastic_graph/schema_definition/rake_tasks"
require "yaml"

module ElasticGraph
  module JSONIngestion
    module SchemaDefinition
      RSpec.describe SchemaArtifactManagerExtension, :in_temp_dir, :rake_task do
        after do
          Thread.current[:eg_schema_load_count] = nil
        end

        it "throws an error if the json_schemas artifact is (attempted to be) changed without json_schema_version being bumped" do
          write_elastic_graph_schema_def_code(json_schema_version: 1)
          expect_all_artifacts_out_of_date_because_they_havent_been_dumped

          # Should succeed, for first artifact.
          expect {
            output = run_rake("schema_artifacts:dump")
            expect(output.lines).to include(
              a_string_including("Dumped", JSON_SCHEMAS_FILE),
              a_string_including("Dumped", versioned_json_schema_file(1))
            )
          }.to change { read_artifact(JSON_SCHEMAS_FILE) }
            .from(a_falsy_value)
            .to(a_string_including("\njson_schema_version: 1\n"))
            .and change { read_artifact(versioned_json_schema_file(1)) }
            .from(a_falsy_value)
            .to(a_string_including("\njson_schema_version: 1\n"))

          expect_up_to_date_artifacts

          write_elastic_graph_schema_def_code(json_schema_version: 2)

          # Should succeed, it is ok to update the schema_version without underlying contents changing.
          expect {
            output = run_rake("schema_artifacts:dump")
            expect(output.lines).to include(
              a_string_including("Dumped", JSON_SCHEMAS_FILE),
              a_string_including("Dumped", versioned_json_schema_file(2))
            )
          }.to change { read_artifact(JSON_SCHEMAS_FILE) }
            .from(a_string_including("\njson_schema_version: 1"))
            .to(a_string_including("\njson_schema_version: 2"))
            .and change { read_artifact(versioned_json_schema_file(2)) }
            .from(a_falsy_value)
            .to(a_string_including("\njson_schema_version: 2\n"))

          write_elastic_graph_schema_def_code(component_suffix: "2", json_schema_version: 2, component_extras: "t.renamed_from 'Component'")
          expect_out_of_date_artifacts

          expect {
            run_rake("schema_artifacts:dump")
          }.to abort_with a_string_including(
            "A change has been attempted to `json_schemas.yaml`",
            "`schema.json_schema_version 3`"
          ).and matching(json_schema_version_setter_location_regex)

          # Still out of date.
          expect_out_of_date_artifacts

          # Decreasing the json_schema_version should also result in a failure.
          write_elastic_graph_schema_def_code(component_suffix: "2", json_schema_version: 1, component_extras: "t.renamed_from 'Component'")
          expect_out_of_date_artifacts

          expect {
            run_rake("schema_artifacts:dump")
          }.to abort_with a_string_including(
            "A change has been attempted to `json_schemas.yaml`",
            "`schema.json_schema_version 3`"
          ).and matching(json_schema_version_setter_location_regex)

          write_elastic_graph_schema_def_code(component_suffix: "2", json_schema_version: 3, component_extras: "t.renamed_from 'Component'")

          # Now dump should succeed, as schema_version has been bumped.
          expect {
            output = run_rake("schema_artifacts:dump")
            expect(output.lines).to include(
              a_string_including("Dumped", JSON_SCHEMAS_FILE),
              a_string_including("Dumped", versioned_json_schema_file(3))
            )
          }.to change { read_artifact(JSON_SCHEMAS_FILE) }
            .from(a_string_including("\njson_schema_version: 2"))
            .to(a_string_including("\njson_schema_version: 3"))
            .and change { read_artifact(versioned_json_schema_file(3)) }
            .from(a_falsy_value)
            .to(a_string_including("\njson_schema_version: 3\n"))

          # Should be able to run `schema_artifacts:dump` idempotently.
          output = run_rake("schema_artifacts:dump")
          expect(output.lines).to include(
            a_string_including("is already up to date", JSON_SCHEMAS_FILE),
            a_string_including("is already up to date", versioned_json_schema_file(3))
          )

          write_elastic_graph_schema_def_code(component_suffix: "3", json_schema_version: 3, component_extras: "t.renamed_from 'Component'")
          expect_out_of_date_artifacts

          expect {
            run_rake("schema_artifacts:dump")
          }.to abort_with a_string_including(
            "A change has been attempted to `json_schemas.yaml`",
            "`schema.json_schema_version 4`"
          ).and matching(json_schema_version_setter_location_regex)

          write_elastic_graph_schema_def_code(
            component_suffix: "3",
            json_schema_version: 3,
            component_extras: "t.renamed_from 'Component'",
            enforce_json_schema_version: false
          )

          expect {
            output = run_rake("schema_artifacts:dump")
            expect(output.lines).to include(
              a_string_including("Dumped", JSON_SCHEMAS_FILE),
              a_string_including("Dumped", versioned_json_schema_file(3))
            )
          }.to change { read_artifact(JSON_SCHEMAS_FILE) }
            .and change { read_artifact(versioned_json_schema_file(3)) }
        end

        it "dumps the ElasticGraph JSON schema metadata only on the internal versioned JSON schema, omitting it from the public copy" do
          write_elastic_graph_schema_def_code(json_schema_version: 1)
          run_rake("schema_artifacts:dump")

          expect(::YAML.safe_load(read_artifact(JSON_SCHEMAS_FILE)).dig("$defs", "Component", "properties", "id")).to eq(
            json_schema_for_keyword_type("ID")
          )

          expect(::YAML.safe_load(read_artifact(versioned_json_schema_file(1))).dig("$defs", "Component", "properties", "id")).to eq(
            json_schema_for_keyword_type("ID", {
              "ElasticGraph" => {
                "type" => "ID!",
                "nameInIndex" => "id"
              }
            })
          )
        end

        it "keeps the ElasticGraph JSON schema metadata up-to-date on all versioned JSON schemas" do
          write_elastic_graph_schema_def_code(json_schema_version: 1)
          run_rake("schema_artifacts:dump")

          expect(::YAML.safe_load(read_artifact(versioned_json_schema_file(1))).dig("$defs", "Component", "properties", "name")).to eq(
            json_schema_for_keyword_type("String", {
              "ElasticGraph" => {
                "type" => "String!",
                "nameInIndex" => "name"
              }
            })
          )

          # Here we add a new field `another: String`
          write_elastic_graph_schema_def_code(json_schema_version: 2, component_name_extras: "\nt.field 'another', 'String!'")
          run_rake("schema_artifacts:dump")

          # It's not added to v1.yaml...
          loaded_v1 = ::YAML.safe_load(read_artifact(versioned_json_schema_file(1)))
          expect(loaded_v1.dig("$defs", "Component", "properties", "name")).to eq(
            json_schema_for_keyword_type("String", {
              "ElasticGraph" => {
                "type" => "String!",
                "nameInIndex" => "name"
              }
            })
          )
          expect(loaded_v1.dig("$defs", "Component", "properties", "another")).to eq(nil)

          # ..but is added to v2.yaml.
          loaded_v2 = ::YAML.safe_load(read_artifact(versioned_json_schema_file(2)))
          expect(loaded_v2.dig("$defs", "Component", "properties", "name")).to eq(
            json_schema_for_keyword_type("String", {
              "ElasticGraph" => {
                "type" => "String!",
                "nameInIndex" => "name"
              }
            })
          )
          expect(loaded_v2.dig("$defs", "Component", "properties", "another")).to eq(
            json_schema_for_keyword_type("String", {
              "ElasticGraph" => {
                "type" => "String!",
                "nameInIndex" => "another"
              }
            })
          )

          # Here we keep the newly added field `another: String` and also change the `name_in_index` of `name`.
          write_elastic_graph_schema_def_code(json_schema_version: 2, component_name_extras: ", name_in_index: 'name2'\nt.field 'another', 'String!'")
          run_rake("schema_artifacts:dump")

          # The `name_in_index` for `name` should be changed to `name2` in the v1 schema...
          loaded_v1 = ::YAML.safe_load(read_artifact(versioned_json_schema_file(1)))
          expect(loaded_v1.dig("$defs", "Component", "properties", "name")).to eq(
            json_schema_for_keyword_type("String", {
              "ElasticGraph" => {
                "type" => "String!",
                "nameInIndex" => "name2"
              }
            })
          )
          expect(loaded_v1.dig("$defs", "Component", "properties", "another")).to eq(nil)

          # ...and in the v2 schema.
          loaded_v2 = ::YAML.safe_load(read_artifact(versioned_json_schema_file(2)))
          expect(loaded_v2.dig("$defs", "Component", "properties", "name")).to eq(
            json_schema_for_keyword_type("String", {
              "ElasticGraph" => {
                "type" => "String!",
                "nameInIndex" => "name2"
              }
            })
          )
          expect(loaded_v2.dig("$defs", "Component", "properties", "another")).to eq(
            json_schema_for_keyword_type("String", {
              "ElasticGraph" => {
                "type" => "String!",
                "nameInIndex" => "another"
              }
            })
          )

          # Here we add a different new field (`ordinal: Int!`), without bumping the version (and using `enforce_json_schema_version: false`
          # to not have to bump the version)...
          write_elastic_graph_schema_def_code(
            json_schema_version: 2,
            component_name_extras: "\nt.field 'ordinal', 'Int!'",
            enforce_json_schema_version: false
          )
          run_rake("schema_artifacts:dump")

          # It should not be added to the v1 schema...
          loaded_v1 = ::YAML.safe_load(read_artifact(versioned_json_schema_file(1)))
          expect(loaded_v1.dig("$defs", "Component", "properties", "ordinal")).to eq(nil)

          # ...but it should be added to the v2 schema.
          loaded_v2 = ::YAML.safe_load(read_artifact(versioned_json_schema_file(2)))
          expect(loaded_v2.dig("$defs", "Component", "properties", "ordinal")).to eq({
            "$ref" => "#/$defs/Int",
            "ElasticGraph" => {"type" => "Int!", "nameInIndex" => "ordinal"}
          })
        end

        it "gives the user a clear error when there is ambiguity about what to do with a renamed or deleted field" do
          # Verify the error message with 1 old JSON schema version (v8).
          write_elastic_graph_schema_def_code(json_schema_version: 8)
          run_rake("schema_artifacts:dump")
          write_elastic_graph_schema_def_code(json_schema_version: 9, omit_component_name_field: true)
          expect { run_rake("schema_artifacts:dump") }.to abort_with <<~EOS
            The `Component.name` field (which existed in JSON schema version 8) no longer exists in the current schema definition.
            ElasticGraph cannot guess what it should do with this field's data when ingesting events at this old version.
            To continue, do one of the following:

            1. If the `Component.name` field has been renamed, indicate this by calling `field.renamed_from "name"` on the renamed field.
            2. If the `Component.name` field has been dropped, indicate this by calling `type.deleted_field "name"` on the `Component` type.
            3. Alternately, if no publishers or in-flight events use JSON schema version 8, delete its file from `json_schemas_by_version`, and no further changes are required.
          EOS

          # Verify the error message with 2 old JSON schema version (v8 and v9).
          # The grammar/phrasing is adjusted slightly (e.g. "versions 8 and 9").
          write_elastic_graph_schema_def_code(json_schema_version: 9)
          run_rake("schema_artifacts:dump")
          write_elastic_graph_schema_def_code(json_schema_version: 10, omit_component_name_field: true)
          expect { run_rake("schema_artifacts:dump") }.to abort_with <<~EOS
            The `Component.name` field (which existed in JSON schema versions 8 and 9) no longer exists in the current schema definition.
            ElasticGraph cannot guess what it should do with this field's data when ingesting events at these old versions.
            To continue, do one of the following:

            1. If the `Component.name` field has been renamed, indicate this by calling `field.renamed_from "name"` on the renamed field.
            2. If the `Component.name` field has been dropped, indicate this by calling `type.deleted_field "name"` on the `Component` type.
            3. Alternately, if no publishers or in-flight events use JSON schema versions 8 or 9, delete their files from `json_schemas_by_version`, and no further changes are required.
          EOS

          # Verify the error message with 3 old JSON schema version (v8, v9, and v10).
          # The grammar/phrasing is adjusted slightly (e.g. "versions 8, 9, and 10").
          write_elastic_graph_schema_def_code(json_schema_version: 10)
          run_rake("schema_artifacts:dump")
          write_elastic_graph_schema_def_code(json_schema_version: 11, omit_component_name_field: true)
          expect { run_rake("schema_artifacts:dump") }.to abort_with <<~EOS
            The `Component.name` field (which existed in JSON schema versions 8, 9, and 10) no longer exists in the current schema definition.
            ElasticGraph cannot guess what it should do with this field's data when ingesting events at these old versions.
            To continue, do one of the following:

            1. If the `Component.name` field has been renamed, indicate this by calling `field.renamed_from "name"` on the renamed field.
            2. If the `Component.name` field has been dropped, indicate this by calling `type.deleted_field "name"` on the `Component` type.
            3. Alternately, if no publishers or in-flight events use JSON schema versions 8, 9, or 10, delete their files from `json_schemas_by_version`, and no further changes are required.
          EOS

          # Demonstrate that these issues can be solved by each of the 3 options given.
          # First, demonstrate indicating the field has been renamed.
          write_elastic_graph_schema_def_code(json_schema_version: 11, omit_component_name_field: true, component_extras: "t.field('full_name', 'String') { |f| f.renamed_from 'name' }")
          run_rake("schema_artifacts:dump")
          delete_artifact(JSON_SCHEMAS_FILE) # so it doesn't force us to increment the version to 5

          # Next, demonstrate indicating the field has been deleted.
          write_elastic_graph_schema_def_code(json_schema_version: 11, omit_component_name_field: true, component_extras: "t.deleted_field 'name'")
          run_rake("schema_artifacts:dump")

          # Finally, demonstrate deleting the old JSON schema version artifacts
          delete_artifact(versioned_json_schema_file(8))
          delete_artifact(versioned_json_schema_file(9))
          delete_artifact(versioned_json_schema_file(10))
          write_elastic_graph_schema_def_code(json_schema_version: 11, omit_component_name_field: true)
          run_rake("schema_artifacts:dump")
        end

        it "gives the user a clear error when there is ambiguity about what to do with a renamed or deleted type" do
          # Verify the error message with 1 old JSON schema version (v1).
          write_elastic_graph_schema_def_code(json_schema_version: 1)
          run_rake("schema_artifacts:dump")
          write_elastic_graph_schema_def_code(json_schema_version: 2, component_suffix: "2")
          expect { run_rake("schema_artifacts:dump") }.to abort_with <<~EOS
            The `Component` type (which existed in JSON schema version 1) no longer exists in the current schema definition.
            ElasticGraph cannot guess what it should do with this type's data when ingesting events at this old version.
            To continue, do one of the following:

            1. If the `Component` type has been renamed, indicate this by calling `type.renamed_from "Component"` on the renamed type.
            2. If the `Component` type has been dropped, indicate this by calling `schema.deleted_type "Component"` on the schema.
            3. Alternately, if no publishers or in-flight events use JSON schema version 1, delete its file from `json_schemas_by_version`, and no further changes are required.
          EOS

          # Verify the error message with 2 old JSON schema version (v1 and v2).
          # The grammar/phrasing is adjusted slightly (e.g. "versions 1 and 2").
          write_elastic_graph_schema_def_code(json_schema_version: 2)
          run_rake("schema_artifacts:dump")
          write_elastic_graph_schema_def_code(json_schema_version: 3, component_suffix: "2")
          expect { run_rake("schema_artifacts:dump") }.to abort_with <<~EOS
            The `Component` type (which existed in JSON schema versions 1 and 2) no longer exists in the current schema definition.
            ElasticGraph cannot guess what it should do with this type's data when ingesting events at these old versions.
            To continue, do one of the following:

            1. If the `Component` type has been renamed, indicate this by calling `type.renamed_from "Component"` on the renamed type.
            2. If the `Component` type has been dropped, indicate this by calling `schema.deleted_type "Component"` on the schema.
            3. Alternately, if no publishers or in-flight events use JSON schema versions 1 or 2, delete their files from `json_schemas_by_version`, and no further changes are required.
          EOS

          # Verify the error message with 3 old JSON schema version (v1, v2, and v3).
          # The grammar/phrasing is adjusted slightly (e.g. "versions 1, 2, and 3").
          write_elastic_graph_schema_def_code(json_schema_version: 3)
          run_rake("schema_artifacts:dump")
          write_elastic_graph_schema_def_code(json_schema_version: 4, component_suffix: "2")
          expect { run_rake("schema_artifacts:dump") }.to abort_with <<~EOS
            The `Component` type (which existed in JSON schema versions 1, 2, and 3) no longer exists in the current schema definition.
            ElasticGraph cannot guess what it should do with this type's data when ingesting events at these old versions.
            To continue, do one of the following:

            1. If the `Component` type has been renamed, indicate this by calling `type.renamed_from "Component"` on the renamed type.
            2. If the `Component` type has been dropped, indicate this by calling `schema.deleted_type "Component"` on the schema.
            3. Alternately, if no publishers or in-flight events use JSON schema versions 1, 2, or 3, delete their files from `json_schemas_by_version`, and no further changes are required.
          EOS

          # Demonstrate that these issues can be solved by each of the 3 options given.
          # First, demonstrate indicating the type has been renamed.
          write_elastic_graph_schema_def_code(json_schema_version: 4, component_suffix: "2", component_extras: "t.renamed_from 'Component'")
          run_rake("schema_artifacts:dump")
          delete_artifact(JSON_SCHEMAS_FILE) # so it doesn't force us to increment the version to 5

          # Next, demonstrate indicating the type has been deleted.
          write_elastic_graph_schema_def_code(json_schema_version: 4, component_suffix: "2", component_extras: "schema.deleted_type 'Component'")
          run_rake("schema_artifacts:dump")

          # Finally, demonstrate deleting the old JSON schema version artifacts
          delete_artifact(versioned_json_schema_file(1))
          delete_artifact(versioned_json_schema_file(2))
          delete_artifact(versioned_json_schema_file(3))
          write_elastic_graph_schema_def_code(json_schema_version: 4, component_suffix: "2")
          run_rake("schema_artifacts:dump")
        end

        it "warns if there are `deleted_*` or `renamed_from` calls that are not needed so the user knows they can remove them" do
          ::File.write("schema.rb", <<~EOS)
            ElasticGraph.define_schema do |schema|
              schema.json_schema_version 1
              schema.deleted_type "SomeType"

              schema.object_type "Widget" do |t|
                t.renamed_from "Widget2"
                t.deleted_field "name"
                t.field "description", "String" do |f|
                  f.renamed_from "old_description"
                end
                t.renamed_from "Widget3"

                t.field "id", "ID"
                t.index "widgets"
              end
            end
          EOS

          output = run_rake("schema_artifacts:dump")
          expect(output.split("\n").first(9).join("\n")).to eq(<<~EOS.strip)
            The schema definition has 5 unneeded reference(s) to deprecated schema elements. These can all be safely deleted:

            1. `schema.deleted_type "SomeType"` at schema.rb:3
            2. `type.renamed_from "Widget2"` at schema.rb:6
            3. `type.deleted_field "name"` at schema.rb:7
            4. `field.renamed_from "old_description"` at schema.rb:9
            5. `type.renamed_from "Widget3"` at schema.rb:11

            Dumped schema artifact to `config/schema/artifacts/datastore_config.yaml`.
          EOS
        end

        it "gives a clear error if excess `deleted_*` or `renamed_from` calls create a conflict" do
          ::File.write("schema.rb", <<~EOS)
            ElasticGraph.define_schema do |schema|
              schema.json_schema_version 1
              schema.deleted_type "Widget"

              schema.object_type "Widget" do |t|
                t.field "id", "ID"
                t.index "widgets"

                t.field "token", "ID" do |f|
                  f.renamed_from "id"
                end
                t.deleted_field "id"
              end
            end
          EOS

          expect {
            run_rake("schema_artifacts:dump")
          }.to abort_with(<<~EOS)
            The schema definition of `Widget` has conflicts. To resolve the conflict, remove the unneeded definitions from the following:

            1. `schema.deleted_type "Widget"` at schema.rb:3


            The schema definition of `Widget.id` has conflicts. To resolve the conflict, remove the unneeded definitions from the following:

            1. `field.renamed_from "id"` at schema.rb:10
            2. `type.deleted_field "id"` at schema.rb:12
          EOS
        end

        it "does not allow a routing or rollover field to be deleted since we cannot index documents without values for those fields" do
          ::File.write("schema.rb", <<~EOS)
            ElasticGraph.define_schema do |schema|
              schema.json_schema_version 1

              schema.object_type "Embedded" do |t|
                t.field "workspace_id", "ID"
                t.field "created_at", "DateTime"
              end

              schema.object_type "Widget" do |t|
                t.field "id", "ID"
                t.field "embedded", "Embedded"
                t.index "widgets" do |i|
                  i.route_with "embedded.workspace_id"
                  i.rollover :yearly, "embedded.created_at"
                end
              end
            end
          EOS

          run_rake("schema_artifacts:dump")

          ::File.write("schema.rb", <<~EOS)
            ElasticGraph.define_schema do |schema|
              schema.json_schema_version 2

              schema.object_type "Embedded" do |t|
                t.field "workspace_id2", "ID", name_in_index: "workspace_id"
                t.deleted_field "workspace_id"

                t.field "created_at2", "DateTime", name_in_index: "created_at"
                t.deleted_field "created_at"
              end

              schema.object_type "Widget" do |t|
                t.field "id", "ID"
                t.field "embedded", "Embedded"
                t.index "widgets" do |i|
                  i.route_with "embedded.workspace_id2"
                  i.rollover :yearly, "embedded.created_at2"
                end
              end
            end
          EOS

          expect { run_rake("schema_artifacts:dump") }.to abort_with(<<~EOS)
            JSON schema version 1 has no field that maps to the routing field path of `Widget.embedded.workspace_id`.
            Since the field path is required for routing, ElasticGraph cannot ingest events that lack it. To continue, do one of the following:

            1. If the `Widget.embedded.workspace_id` field has been renamed, indicate this by calling `field.renamed_from "workspace_id"` on the renamed field rather than using `deleted_field`.
            2. Alternately, if no publishers or in-flight events use JSON schema version 1, delete its file from `json_schemas_by_version`, and no further changes are required.


            JSON schema version 1 has no field that maps to the rollover field path of `Widget.embedded.created_at`.
            Since the field path is required for rollover, ElasticGraph cannot ingest events that lack it. To continue, do one of the following:

            1. If the `Widget.embedded.created_at` field has been renamed, indicate this by calling `field.renamed_from "created_at"` on the renamed field rather than using `deleted_field`.
            2. Alternately, if no publishers or in-flight events use JSON schema version 1, delete its file from `json_schemas_by_version`, and no further changes are required.
          EOS
        end

        let(:json_schema_version_setter_location_regex) do
          # In `write_elastic_graph_schema_def_code` `json_schema_version` is called on the 7th line of
          # the file written to `schema.rb` (after the 5-line double-load guard). See below.
          #
          # Note: on Ruby 3.3, the path here winds up being slightly different; instead of just `schema.rb` it is something like:
          # `../d20240216-23551-cvdjzo/schema.rb`. I think it's related to the temp directory we run these specs within.
          /line 7 at `(\S*\/?)schema\.rb`/
        end

        def write_elastic_graph_schema_def_code(json_schema_version:, component_suffix: "", component_name_extras: "", component_extras: "", omit_component_name_field: false, enforce_json_schema_version: true)
          code = <<~EOS
            Thread.current[:eg_schema_load_count] = (Thread.current[:eg_schema_load_count] || 0) + 1
            if Thread.current[:eg_schema_load_count] > 1
              raise "Schema file \#{__FILE__} was loaded \#{Thread.current[:eg_schema_load_count]} times in a single run!"
            end

            ElasticGraph.define_schema do |schema|
              schema.json_schema_version #{json_schema_version}
              #{"schema.enforce_json_schema_version false" unless enforce_json_schema_version}
              schema.enum_type "Size" do |t|
                t.values "SMALL", "MEDIUM", "LAGE"
              end

              schema.object_type "MechanicalPart" do |t|
                t.field "id", "ID!" do |f|
                  f.directive "fromExtensionModule"
                end

                t.index "mechanical_parts"
              end

              schema.object_type "ElectricalPart" do |t|
                t.field "id", "ID!"
                t.field "size", "Size"
                t.index "electrical_parts"
              end

              schema.union_type "Part" do |t|
                t.subtypes %w[MechanicalPart ElectricalPart]
              end

              schema.object_type "ComponentDesigner#{component_suffix}" do |t|
                t.field "id", "ID!"
                t.field "designed_component_names", "[String!]!"
                t.index "component_designers#{component_suffix}"
              end

              schema.object_type "Component#{component_suffix}" do |t|
                t.field "id", "ID!"
                #{%(t.field "name", "String!"#{component_name_extras}) unless omit_component_name_field}
                t.field "designer_id", "ID"
                t.index "components#{component_suffix}", number_of_shards: 5

                t.derive_indexed_type_fields "ComponentDesigner#{component_suffix}", from_id: "designer_id" do |derive|
                  derive.append_only_set "designed_component_names", from: "name"
                end
                #{component_extras}
              end
            end
          EOS

          ::File.write("schema.rb", code)
        end

        def expect_up_to_date_artifacts
          output = nil

          expect {
            output = run_rake("schema_artifacts:check")
          }.not_to raise_error

          expect(output).to include(DATASTORE_CONFIG_FILE, JSON_SCHEMAS_FILE, "up to date")
        end

        def expect_all_artifacts_out_of_date_because_they_havent_been_dumped
          expect {
            run_rake("schema_artifacts:check")
          }.to abort_with { |error|
            expect(error.message).to eq(<<~EOS.strip)
              5 schema artifact(s) are out of date. Run `bundle exec rake schema_artifacts:dump` to update the following artifact(s):

              1. config/schema/artifacts/datastore_config.yaml (file does not exist)
              2. config/schema/artifacts/json_schemas.yaml (file does not exist)
              3. config/schema/artifacts/json_schemas_by_version/v1.yaml (file does not exist)
              4. config/schema/artifacts/runtime_metadata.yaml (file does not exist)
              5. config/schema/artifacts/schema.graphql (file does not exist)
            EOS
          }
        end

        def expect_out_of_date_artifacts
          expect {
            run_rake("schema_artifacts:check")
          }.to abort_with a_string_including("out of date", DATASTORE_CONFIG_FILE, JSON_SCHEMAS_FILE)
        end

        def run_rake(*args)
          Thread.current[:eg_schema_load_count] = nil

          # The schema definition code written by `write_elastic_graph_schema_def_code` uses a
          # `fromExtensionModule` directive, which this extension module defines.
          extension_module = ::Module.new do
            def as_active_instance
              raw_sdl "directive @fromExtensionModule on FIELD_DEFINITION"
              super
            end
          end

          super(*args) do |output|
            ::ElasticGraph::SchemaDefinition::RakeTasks.new(
              schema_element_name_form: :snake_case,
              index_document_sizes: true,
              path_to_schema: "schema.rb",
              schema_artifacts_directory: "config/schema/artifacts",
              extension_modules: [APIExtension, extension_module],
              output: output
            )
          end
        end

        def read_artifact(*name_parts)
          path = ::File.join("config", "schema", "artifacts", *name_parts)
          ::File.exist?(path) && ::File.read(path)
        end

        def delete_artifact(*name_parts)
          ::File.delete(::File.join("config", "schema", "artifacts", *name_parts))
        end

        def versioned_json_schema_file(version)
          ::File.join(JSON_SCHEMAS_BY_VERSION_DIRECTORY, "v#{version}.yaml")
        end

        def json_schema_for_keyword_type(type, extras = {})
          {
            "allOf" => [
              {"$ref" => "#/$defs/#{type}"},
              {"maxLength" => DEFAULT_MAX_KEYWORD_LENGTH}
            ]
          }.merge(extras)
        end
      end
    end
  end
end
