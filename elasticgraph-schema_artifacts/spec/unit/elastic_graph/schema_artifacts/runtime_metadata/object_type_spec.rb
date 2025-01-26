# Copyright 2024 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/schema_artifacts/runtime_metadata/object_type"
require "elastic_graph/spec_support/runtime_metadata_support"

module ElasticGraph
  module SchemaArtifacts
    module RuntimeMetadata
      RSpec.describe ObjectType do
        include RuntimeMetadataSupport

        it "builds from a minimal hash" do
          type = ObjectType.from_hash({})

          expect(type).to eq ObjectType.new(
            update_targets: [],
            index_definition_names: [],
            graphql_fields_by_name: {},
            elasticgraph_category: nil,
            source_type: nil,
            graphql_only_return_type: false,
            default_graphql_resolver: nil
          )
        end

        it "exposes `elasticgraph_category` as a symbol while keeping it as a string in dumped form" do
          type = ObjectType.from_hash({"elasticgraph_category" => "scalar_aggregated_values"})

          expect(type.elasticgraph_category).to eq :scalar_aggregated_values
          expect(type.to_dumpable_hash).to include("elasticgraph_category" => "scalar_aggregated_values")
        end

        it "exposes `default_graphql_resolver` as a symbol while keeping it as a string in dumped form" do
          type = ObjectType.from_hash({"default_graphql_resolver" => "self"})

          expect(type.default_graphql_resolver).to eq :self
          expect(type.to_dumpable_hash).to include("default_graphql_resolver" => "self")
        end

        it "models `graphql_only_return_type` as `true` or `nil` so that our runtime metadata pruning can omit nils" do
          type = ObjectType.from_hash({})

          expect(type.graphql_only_return_type).to eq false
          expect(type.to_dumpable_hash).to include("graphql_only_return_type" => nil)

          type = ObjectType.from_hash({"graphql_only_return_type" => true})

          expect(type.graphql_only_return_type).to eq true
          expect(type.to_dumpable_hash).to include("graphql_only_return_type" => true)
        end

        it "omits GraphQL fields that have no meaningful metadata" do
          type = object_type_with(
            default_graphql_resolver: :self,
            graphql_fields_by_name: {
              "foo1" => graphql_field_with(resolver: :self, name_in_index: "foo1"),
              "foo2" => graphql_field_with(resolver: :self, name_in_index: "foo2_in_index"),
              "foo3" => graphql_field_with(resolver: :self, name_in_index: "foo3", relation: relation_with),
              "foo4" => graphql_field_with(resolver: :self, name_in_index: "foo4", computation_detail: computation_detail_with),
              "foo5" => graphql_field_with(resolver: :other, name_in_index: "foo5"),
              "foo6" => graphql_field_with(resolver: :self, name_in_index: nil)
            }
          )

          expect(type.graphql_fields_by_name.keys).to contain_exactly("foo2", "foo3", "foo4", "foo5")
        end
      end
    end
  end
end
