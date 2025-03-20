# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  class GraphQL
    module Aggregation
      # Grouping adapter that uses a `composite` aggregation.
      #
      # For now, only used for the outermost "root" aggregations but may be used for sub-aggregations in the future.
      module CompositeGroupingAdapter
        class << self
          def meta_name
            "comp"
          end

          def grouping_detail_for(query)
            sources = build_sources(query)

            inner_clauses = yield
            inner_clauses = nil if inner_clauses.empty?

            return AggregationDetail.new(inner_clauses, {}) if sources.empty?

            clauses = {
              query.name => {
                "composite" => {
                  "size" => query.paginator.requested_page_size,
                  "sources" => sources,
                  "after" => composite_after(query)
                }.compact,
                "aggs" => inner_clauses
              }.compact
            }

            AggregationDetail.new(clauses, {"buckets_path" => [query.name]})
          end

          def prepare_response_buckets(sub_agg, buckets_path, meta)
            sub_agg.dig(*buckets_path).fetch("buckets").map do |bucket|
              bucket.merge({"doc_count_error_upper_bound" => 0})
            end
          end

          private

          def composite_after(query)
            return unless (cursor = query.paginator.search_after)
            expected_keys = query.groupings.map(&:key)

            if cursor.sort_values.keys.sort == expected_keys.sort
              cursor.sort_values
            else
              raise ::GraphQL::ExecutionError, "`#{cursor.encode}` is not a valid cursor for the current groupings."
            end
          end

          def build_sources(query)
            # We don't want documents that have no value for a grouping field to be omitted, so we set `missing_bucket: true`.
            # https://www.elastic.co/guide/en/elasticsearch/reference/8.11/search-aggregations-bucket-composite-aggregation.html#_missing_bucket
            grouping_options = if query.paginator.search_in_reverse?
              {"order" => "desc", "missing_bucket" => true}
            else
              {"missing_bucket" => true}
            end

            query.groupings.map do |grouping|
              {grouping.key => grouping.composite_clause(grouping_options: grouping_options)}
            end
          end
        end
      end
    end
  end
end
