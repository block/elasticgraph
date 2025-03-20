# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphql/aggregation/key"

module ElasticGraph
  class GraphQL
    module Aggregation
      RSpec.shared_context "sub-aggregation support" do |grouping_adapter|
        define_method :outer_meta do |hash = {}, size: 50|
          {"size" => size, "adapter" => grouping_adapter.meta_name}.merge(hash)
        end

        def inner_terms_meta(hash = {})
          {"merge_into_bucket" => {}}.merge(hash)
        end

        def inner_date_meta(hash = {})
          {"merge_into_bucket" => {"doc_count_error_upper_bound" => 0}}.merge(hash)
        end

        define_method :sub_aggregation_query_of do |**options|
          super(grouping_adapter: grouping_adapter, **options)
        end
      end

      module SubAggregationRefinements
        refine ::Hash do
          # Helper method that can be used to add a missing value bucket aggregation to an
          # existing aggregation hash. Defined as a refinement to support a chainable syntax
          # in order to minimize churn in our specs at the point we added missing value buckets.
          def with_missing_value_bucket(count, extras = {})
            grouped_field = SubAggregationRefinements.grouped_field_from(self)

            missing_value_bucket = extras.merge({
              "doc_count" => count,
              "meta" => (extras.empty? ? nil : dig(grouped_field, "meta"))
            }.compact)

            merge({
              Aggregation::Key.missing_value_bucket_key(grouped_field) => missing_value_bucket
            })
          end
        end

        extend ::RSpec::Matchers

        def self.grouped_field_from(agg_hash)
          grouped_field_candidates = agg_hash.except(
            "doc_count", "meta", "key", "key_as_string",
            "doc_count_error_upper_bound",
            "sum_other_doc_count"
          ).keys

          # We expect only one candidate; here we use an expectation that will show them all if there are more.
          expect(grouped_field_candidates).to eq([grouped_field_candidates.first])
          grouped_field_candidates.first
        end
      end
    end
  end
end
