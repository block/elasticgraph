# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/apollo/schema_definition/api_extension"
require "elastic_graph/graphql"
require "elastic_graph/indexer"
require "elastic_graph/schema_definition/rake_tasks"

module ElasticGraph
  # The indexer writes every field of the update target, so a document it indexes has an explicit `null` for an id
  # the event omitted. A document indexed before an `apollo_entity_ref_field`'s backing id field was added to the
  # schema has no key for it at all, and must resolve the same way.
  RSpec.describe "Resolving Apollo entity refs on an evolving schema", :ingests_json_data, :factories, :capture_logs, :in_temp_dir, :rake_task do
    let(:path_to_schema) { "config/schema.rb" }

    before do
      ::FileUtils.mkdir_p "config"
      dump_schema_artifacts(json_schema_version: 1)

      # The factory record carries `owner_id` and `owner_ids`, but this schema version defines neither, so the
      # indexer drops them and the stored document has no key for either (rather than an explicit `null`).
      boot(Indexer).processor.process([build_upsert_event(:component, id: "c1")], refresh_indices: true)
    end

    it "resolves an entity ref field to `null` on a document indexed before the backing id field was defined" do
      dump_schema_artifacts(json_schema_version: 2, component_extras: <<~EOS)
        t.field "owner_id", "ID", indexing_only: true
        t.apollo_entity_ref_field "owner", "ComponentOwner", id_field_name_in_index: "owner_id"
      EOS

      data = execute_expecting_no_errors(<<~QUERY)
        query {
          components {
            nodes {
              id
              owner { token }
            }
          }
        }
      QUERY

      expect(data).to eq({"components" => {"nodes" => [{"id" => "c1", "owner" => nil}]}})
    end

    it "resolves an entity ref list field to an empty list on a document indexed before the backing ids field was defined" do
      dump_schema_artifacts(json_schema_version: 2, component_extras: <<~EOS)
        t.field "owner_ids", "[ID!]!", indexing_only: true
        t.apollo_entity_ref_field "owners", "[ComponentOwner!]!", id_field_name_in_index: "owner_ids"
      EOS

      data = execute_expecting_no_errors(<<~QUERY)
        query {
          components {
            nodes {
              id
              owners { token }
            }
          }
        }
      QUERY

      expect(data).to eq({"components" => {"nodes" => [{"id" => "c1", "owners" => []}]}})
    end

    def dump_schema_artifacts(json_schema_version:, component_extras: "")
      # A pared down definition of our normal test schema `Component` type and its `ComponentOwner` entity ref.
      ::File.write(path_to_schema, <<~EOS)
        ElasticGraph.define_schema do |schema|
          schema.json_schema_version #{json_schema_version}

          schema.object_type "Component" do |t|
            t.field "id", "ID!"
            #{component_extras}
            t.index "components"
          end

          schema.object_type "ComponentOwner" do |t|
            t.field "token", "ID"
            t.apollo_key fields: "token", resolvable: false
          end
        end
      EOS

      run_rake "schema_artifacts:dump" do |output|
        SchemaDefinition::RakeTasks.new(
          schema_element_name_form: :snake_case,
          extension_modules: json_ingestion_schema_definition_extension_modules([Apollo::SchemaDefinition::APIExtension]),
          index_document_sizes: true,
          path_to_schema: path_to_schema,
          schema_artifacts_directory: "config/schema/artifacts",
          output: output
        )
      end
    end

    def boot(klass)
      klass.from_yaml_file(CommonSpecHelpers.test_settings_file)
    end

    def execute_expecting_no_errors(query)
      response = boot(GraphQL).graphql_query_executor.execute(query)
      expect(response["errors"]).to be nil
      response.fetch("data")
    end
  end
end
