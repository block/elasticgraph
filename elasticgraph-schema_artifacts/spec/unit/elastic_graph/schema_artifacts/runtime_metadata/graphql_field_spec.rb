# Copyright 2024 - 2025 Block, Inc.
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
            computation_detail: nil,
            name_in_index: nil,
            relation: nil,
            resolver: nil
          )
        end

        it "offers `with_computation_detail` updating aggregation detail" do
          field = GraphQLField.new(
            computation_detail: nil,
            name_in_index: nil,
            relation: nil,
            resolver: configured_graphql_resolver(:self)
          )

          updated = field.with_computation_detail(
            empty_bucket_value: 0,
            function: :sum
          )

          expect(updated.computation_detail).to eq(ComputationDetail.new(
            empty_bucket_value: 0,
            function: :sum
          ))
        end

        it "exposes `resolver` as nil when it is unset" do
          field = GraphQLField.from_hash({})

          expect(field.resolver).to eq nil
          expect(field.to_dumpable_hash).to include("resolver" => nil)
        end
      end
    end
  end
end
