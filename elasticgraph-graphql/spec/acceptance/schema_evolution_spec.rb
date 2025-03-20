# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphql"
require "elastic_graph/indexer"
require "elastic_graph/schema_definition/rake_tasks"
require "support/graphql"

module ElasticGraph
  RSpec.describe "Querying an evolving schema", :uses_datastore, :factories, :capture_logs, :in_temp_dir, :rake_task do
    include GraphQLSupport
    let(:path_to_schema) { "config/schema.rb" }

    before do
      ::FileUtils.mkdir_p "config"
    end

    it "treats a new list field as having a count of `0` on documents that were indexed before the field was defined" do
      dump_schema_artifacts(json_schema_version: 1)
      boot(Indexer).processor.process([build_upsert_event(:team, id: "t1", owners: [])], refresh_indices: true)

      dump_schema_artifacts(json_schema_version: 2, team_extras: <<~EOS)
        t.field 'owners', '[String!]!' do |f|
          f.mapping type: "object"
        end
      EOS

      data = call_graphql_query(<<~QUERY, gql: boot(GraphQL)).fetch("data")
        query {
          teams(filter: {owners: {count: {lt: 1}}}) {
            nodes { id }
          }
        }
      QUERY

      expect(data).to eq({"teams" => {"nodes" => [{"id" => "t1"}]}})
    end

    def dump_schema_artifacts(json_schema_version:, team_extras: "")
      # This is a pared down schema definition of our normal test schema `Team` type.
      ::File.write(path_to_schema, <<~EOS)
        ElasticGraph.define_schema do |schema|
          schema.json_schema_version #{json_schema_version}

          schema.object_type "Team" do |t|
            t.field "id", "ID!"
            t.field "league", "String"
            t.field "formed_on", "Date"
            t.field "past_names", "[String!]!"
            #{team_extras}
            t.index "teams" do |i|
              i.route_with "league"
              i.rollover :yearly, "formed_on"
            end
          end
        end
      EOS

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

    def boot(klass)
      klass.from_yaml_file(CommonSpecHelpers.test_settings_file)
    end
  end
end
