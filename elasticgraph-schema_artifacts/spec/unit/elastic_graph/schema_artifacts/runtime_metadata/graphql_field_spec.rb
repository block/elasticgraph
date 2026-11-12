# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/schema_artifacts/runtime_metadata/graphql_field"
require "elastic_graph/spec_support/runtime_metadata_support"

module ElasticGraph
  module SchemaArtifacts
    module RuntimeMetadata
      RSpec.describe GraphQLField do
        include RuntimeMetadataSupport

        it "builds from a minimal hash" do
          field = GraphQLField.from_hash({})

          expect(field).to eq GraphQLField.new(
            computation_function: nil,
            name_in_index: nil,
            relation: nil,
            resolver: nil,
            object_grouping_leaf_type_name: nil
          )
        end

        it "round-trips `computation_function` through the dumped form, symbolizing it on load" do
          field = GraphQLField.new(
            computation_function: :sum,
            name_in_index: nil,
            relation: nil,
            resolver: configured_graphql_resolver(:self),
            object_grouping_leaf_type_name: nil
          )

          expect(field.to_dumpable_hash).to include("computation_function" => "sum")
          expect(GraphQLField.from_hash(field.to_dumpable_hash).computation_function).to eq :sum
        end

        it "exposes `resolver` as nil when it is unset" do
          field = GraphQLField.from_hash({})

          expect(field.resolver).to eq nil
          expect(field.to_dumpable_hash).to include("resolver" => nil)
        end

        it "round-trips `object_grouping_leaf_type_name` through the dumped form" do
          field = graphql_field_with(object_grouping_leaf_type_name: "Int")

          expect(GraphQLField.from_hash(field.to_dumpable_hash)).to eq field
        end

        it "is needed when `object_grouping_leaf_type_name` is set" do
          field = graphql_field_with(name_in_index: "name", object_grouping_leaf_type_name: "Int")

          expect(field.needed?("name")).to be true
          expect(field.with(object_grouping_leaf_type_name: nil).needed?("name")).to be false
        end
      end
    end
  end
end
