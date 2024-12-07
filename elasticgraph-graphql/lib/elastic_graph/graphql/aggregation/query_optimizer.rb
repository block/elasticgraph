# Copyright 2024 Block, Inc.
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
      # This class is used by `DatastoreQuery.perform` to optimize away an inefficiency that's present in
      # our aggregations API. To explain what this does, it's useful to see an example:
      #
      # ```
      # query WigdetsBySizeAndColor($filter: WidgetFilterInput) {
      #   by_size: widgetAggregations(filter: $filter) {
      #     edges { node {
      #       size
      #       count
      #     } }
      #   }
      #
      #   by_color: widgetAggregations(filter: $filter) {
      #     edges { node {
      #       color
      #       count
      #     } }
      #   }
      # }
      # ```
      #
      # With this API, two separate datastore queries get built--one for `by_size`, and one
      # for `by_color`. While we're able to send them to the datastore in a single `msearch` request,
      # as it allows a single search to have multiple aggregations in it. The aggregations
      # API we offered before April 2023 directly supported this, allowing for more efficient
      # queries. (But it had other significant downsides).
      #
      # We found that sending 2 queries is significantly slower than sending one combined query
      # (from benchmarks/aggregations_old_vs_new_api.rb):
      #
      # Benchmarks for old API (300 times):
      # Average took value: 15
      # Median took value: 14
      # P99 took value: 45
      #
      # Benchmarks for new API (300 times):
      # Average took value: 28
      # Median took value: 25
      # P99 took value: 75
      #
      # This class optimizes this case by merging `DatastoreQuery` objects together when we can safely do so,
      # in order to execute fewer datastore queries. Notably, while this was designed for this specific
      # aggregations case, the merging logic can also apply in non-aggregations case.
      #
      # Note that we want to err on the side of safety here. We only merge queries if their datastore
      # payloads are byte-for-byte identical when aggregations are excluded. There are some cases where
      # we _could_ merge slightly differing queries in clever ways (for example, if the only difference is
      # `track_total_hits: false` vs `track_total_hits: true`, we could merge to a single query with
      # `track_total_hits: true`), but that's significantly more complex and error prone, so we do not do it.
      # We can always improve this further in the future to cover more cases.
      #
      # NOTE: the `QueryOptimizer` assumes that `Aggregation::Query` will always produce aggregation keys
      # using `Aggregation::Query#name` such that `Aggregation::Key.extract_aggregation_name_from` is able
      # to extract the original name from response keys. If that is violated, it will not work properly and
      # subtle bugs can result. However, we have a test helper method which is hooked into our unit and
      # integration tests for `DatastoreQuery` (`verify_aggregations_satisfy_optimizer_requirements`) which
      # verifies that this requirement is satisfied.
      class QueryOptimizer
        def self.optimize_queries(queries)
          return {} if queries.empty?
          optimizer = new(queries, logger: (_ = queries.first).logger)
          responses_by_query = yield optimizer.merged_queries
          optimizer.unmerge_responses(responses_by_query)
        end

        def initialize(original_queries, logger:)
          @original_queries = original_queries
          @logger = logger
          last_id = 0
          @unique_prefix_by_query = ::Hash.new { |h, k| h[k] = "#{last_id += 1}_" }
        end

        def merged_queries
          original_queries_by_merged_query.keys
        end

        def unmerge_responses(responses_by_merged_query)
          original_queries_by_merged_query.flat_map do |merged, originals|
            # When we only had a single query to start with, we didn't change the query at all, and don't need to unmerge the response.
            needs_unmerging = originals.size > 1

            originals.filter_map do |orig|
              if (merged_response = responses_by_merged_query[merged])
                response = needs_unmerging ? unmerge_response(merged_response, orig) : merged_response
                [orig, response]
              end
            end
          end.to_h
        end

        private

        def original_queries_by_merged_query
          @original_queries_by_merged_query ||= queries_by_merge_key.values.to_h do |original_queries|
            [merge_queries(original_queries), original_queries]
          end
        end

        NO_AGGREGATIONS = {}

        def queries_by_merge_key
          @original_queries.group_by do |query|
            # Here we group queries in the simplest, safest way possible: queries are safe to merge if
            # their datastore payloads are byte-for-byte identical, excluding aggregations.
            query.with(aggregations: NO_AGGREGATIONS)
          end
        end

        def merge_queries(queries)
          # If we only have a single query, there's nothing to merge!
          return (_ = queries.first) if queries.one?

          all_aggs_by_name = queries.flat_map do |query|
            # It's possible for two queries to have aggregations with the same name but different parameters.
            # In a merged query, each aggregation must have a different name. Here we guarantee that by adding
            # a numeric prefix to the aggregations. For example, if both `query1` and `query2` have a `by_size`
            # aggregation, on the merged query we'll have a `1_by_size` aggregation and a `2_by_size` aggregation.
            prefix = @unique_prefix_by_query[query]
            query.aggregations.values.map do |agg|
              agg.with(name: "#{prefix}#{agg.name}")
            end
          end.to_h { |agg| [agg.name, agg] }

          @logger.info({
            "message_type" => "AggregationQueryOptimizerMergedQueries",
            "query_count" => queries.size,
            "aggregation_count" => all_aggs_by_name.size,
            "aggregation_names" => all_aggs_by_name.keys.sort
          })

          (_ = queries.first).with(aggregations: all_aggs_by_name)
        end

        # "Unmerges" a response to convert it to what it woulud have been if we hadn't merged queries.
        # To do that, we need to do two things:
        #
        # - Filter down the aggregations to just the ones that are for the original query.
        # - Remove the query-specific prefix (e.g. `1_`) from the parts of the response that
        #   contain the aggregation name.
        def unmerge_response(response_from_merged_query, original_query)
          # If there are no aggregations, there's nothing to unmerge--just return it as is.
          return response_from_merged_query unless (aggs = response_from_merged_query["aggregations"])

          prefix = @unique_prefix_by_query[original_query] # : ::String
          agg_names = original_query.aggregations.keys.map { |name| "#{prefix}#{name}" }.to_set

          filtered_aggs = aggs
            .select { |key, agg_data| agg_names.include?(Key.extract_aggregation_name_from(key)) }
            .to_h do |key, agg_data|
              [key.delete_prefix(prefix), strip_prefix_from_agg_data(agg_data, prefix, key)]
            end

          response_from_merged_query.merge("aggregations" => filtered_aggs)
        end

        def strip_prefix_from_agg_data(agg_data, prefix, key)
          case agg_data
          when ::Hash
            agg_data.to_h do |sub_key, sub_data|
              sub_key = sub_key.delete_prefix(prefix) if sub_key.start_with?(key)
              [sub_key, strip_prefix_from_agg_data(sub_data, prefix, key)]
            end
          when ::Array
            agg_data.map do |element|
              strip_prefix_from_agg_data(element, prefix, key)
            end
          else
            agg_data
          end
        end
      end
    end
  end
end
