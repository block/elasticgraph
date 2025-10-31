# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphql/aggregation/query"
require "support/aggregations_helpers"

module ElasticGraph
  class GraphQL
    module Aggregation
      RSpec.describe Query do
        include AggregationsHelpers

        describe "AggregationDetail#wrap_with_grouping" do
          let(:query) do
            aggregation_query_of(
              first: 10,
              needs_doc_count_error: true
            )
          end

          let(:detail) do
            AggregationDetail.new(
              {"computation" => {"sum" => {"field" => "amount"}}},
              {"some" => "meta"}
            )
          end

          context "when grouping handles missing values via placeholder" do
            it "does not create a separate missing aggregation" do
              grouping = field_term_grouping_of("foo", "bar", missing_value_placeholder: "MISSING")
              wrapped = detail.wrap_with_grouping(grouping, query: query)

              # Should only have the main aggregation, not a missing one
              expect(wrapped.clauses.keys).to eq(["foo.bar"])
              expect(wrapped.clauses.keys).not_to include("foo.bar:m")
            end
          end

          context "when grouping does not handle missing values via placeholder" do
            it "does not include missing_values in the metadata" do
              grouping = field_term_grouping_of("foo", "bar", missing_value_placeholder: nil)
              wrapped = detail.wrap_with_grouping(grouping, query: query)

              expect(wrapped.meta).to include("buckets_path" => ["foo.bar"])
              expect(wrapped.meta).not_to include("missing_values")
            end

            it "creates a separate missing aggregation" do
              grouping = field_term_grouping_of("foo", "bar", missing_value_placeholder: nil)
              wrapped = detail.wrap_with_grouping(grouping, query: query)

              # Should have both the main aggregation and a missing one
              expect(wrapped.clauses.keys).to include("foo.bar")
              expect(wrapped.clauses.keys).to include("foo.bar:m")  # Key.missing_value_bucket_key uses ":m" suffix
            end
          end
        end
      end
    end
  end
end
