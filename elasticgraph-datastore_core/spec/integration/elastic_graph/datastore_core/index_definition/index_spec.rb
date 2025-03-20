# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/datastore_core/index_definition"
require "stringio"
require_relative "implementation_shared_examples"

module ElasticGraph
  class DatastoreCore
    module IndexDefinition
      RSpec.describe Index, :uses_datastore do
        # Use different index names than any other tests use, because most tests expect a specific index
        # configuration (based on `config/schema.graphql`) and we do not want to mess with it here.
        let(:index_prefix) { unique_index_name }
        let(:widgets_index_name) { "#{index_prefix}_widgets" }
        let(:components_index_name) { "#{index_prefix}_components" }
        let(:output_io) { StringIO.new }
        let(:schema_definition) do
          lambda do |schema|
            schema.object_type "Component" do |t|
              t.field "id", "ID!"
              t.field "name", "String"
              t.index components_index_name
            end
          end
        end

        include_examples "an IndexDefinition implementation (integration specs)" do
          def configure_index(index)
          end
        end

        describe "#delete_from_datastore", :builds_admin do
          let(:datastore_core) do
            build_datastore_core(schema_definition: schema_definition)
          end

          before do
            build_admin(datastore_core: datastore_core).cluster_configurator.configure_cluster(output_io)
          end

          it "deletes non-rollover index definition" do
            index_definition = datastore_core.index_definitions_by_name.fetch(components_index_name)

            expect {
              index_definition.delete_from_datastore(main_datastore_client)
            }.to change { main_datastore_client.get_index(index_definition.name) }
              .from(a_hash_including(
                "mappings" => a_hash_including("properties" => a_hash_including("id", "name")),
                "settings" => a_kind_of(Hash)
              ))
              .to({})
          end

          it "ignores non-existing index" do
            index_def_not_exist = index_def_named("does_not_exist")

            expect {
              index_def_not_exist.delete_from_datastore(main_datastore_client)
            }.not_to raise_error
          end
        end

        describe "related indices" do
          it "returns an empty list as it never has any related indices" do
            datastore_core = build_datastore_core(schema_definition: schema_definition)
            index_definition = datastore_core.index_definitions_by_name.fetch(components_index_name)

            expect(index_definition.rollover_index_template?).to be false
            expect(index_definition.related_rollover_indices(main_datastore_client)).to eq []
            expect(index_definition.known_related_query_rollover_indices).to eq []
          end
        end

        def index_def_named(name, rollover: nil)
          runtime_metadata = SchemaArtifacts::RuntimeMetadata::IndexDefinition.new(
            route_with: nil,
            rollover: nil,
            default_sort_fields: [],
            current_sources: [SELF_RELATIONSHIP_NAME],
            fields_by_path: {}
          )

          DatastoreCore::IndexDefinition.with(
            name: name,
            config: datastore_core.config,
            runtime_metadata: runtime_metadata,
            datastore_clients_by_name: datastore_core.clients_by_name
          )
        end
      end
    end
  end
end
