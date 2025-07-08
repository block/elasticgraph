# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphql/aggregation/key"
require "elastic_graph/graphql/datastore_query"
require "elastic_graph/graphql/filtering/field_path"
require "elastic_graph/support/hash_util"

module ElasticGraph
  class GraphQL
    module Aggregation
      class Query < ::Data.define(
        # Unique name for the aggregation
        :name,
        # Whether or not we need to get the document count for each bucket.
        :needs_doc_count,
        # Whether or not we need to get the error on the document count to satisfy the sub-aggregation query.
        # https://www.elastic.co/guide/en/elasticsearch/reference/8.10/search-aggregations-bucket-terms-aggregation.html#_per_bucket_document_count_error
        :needs_doc_count_error,
        # Filter to apply to this sub-aggregation.
        :filter,
        # Paginator for handling size and other pagination concerns.
        :paginator,
        # A sub-aggregation query can have sub-aggregations of its own.
        :sub_aggregations,
        # Collection of `Computation` objects that specify numeric computations to perform.
        :computations,
        # Collection of `DateHistogramGrouping`, `FieldTermGrouping`, and `ScriptTermGrouping` objects that specify how this sub-aggregation should be grouped.
        :groupings,
        # Adapter to use for groupings.
        :grouping_adapter
      )
        def needs_total_doc_count?
          # We only need a total document count when there are NO groupings and the doc count is requested.
          # The datastore will return the number of hits in each grouping automatically, so we don't need
          # a total doc count when there are groupings. And when the query isn't requesting the field, we
          # don't need it, either.
          needs_doc_count && groupings.empty?
        end

        # Builds an aggregations hash. The returned value has a few different cases:
        #
        # - If `size` is 0, or `groupings` and `computations` are both empty, we return an empty hash,
        #   so that `to_datastore_body` is an empty hash. We do this so that we avoid sending
        #   the datastore any sort of aggregations query in these cases, as the client is not
        #   requesting any aggregation data.
        # - If `SINGLETON_CURSOR` was provide for either `before` or `after`, we also return an empty hash,
        #   because we know there cannot be any results to return--the cursor is a reference to
        #   the one and only item in the list, and nothing can exist before or after it.
        # - Otherwise, we return an aggregatinos hash based on the groupings, computations, and sub-aggregations.
        def build_agg_hash(filter_interpreter)
          build_agg_detail(filter_interpreter, field_path: [], parent_queries: [])&.clauses || {}
        end

        def build_agg_detail(filter_interpreter, field_path:, parent_queries:, nested: false)
          return nil if paginator.desired_page_size.zero? || paginator.paginated_from_singleton_cursor?
          queries = parent_queries + [self] # : ::Array[Query]

          filter_detail(filter_interpreter, field_path, nested: nested) do
            grouping_adapter.grouping_detail_for(self) do
              Support::HashUtil.disjoint_merge(computations_detail, sub_aggregation_detail(filter_interpreter, queries))
            end
          end
        end

        private

        def filter_detail(filter_interpreter, field_path, nested: false)
          filtering_field_path = Filtering::FieldPath.of(field_path.filter_map(&:name_in_index))

          # When we're dealing with a nested sub-aggregation, we need to apply the nested transformation
          # to the filtering field path to ensure count filters work correctly.
          # This is necessary because nested fields create separate document contexts in Elasticsearch/OpenSearch.
          filtering_field_path = filtering_field_path.nested if nested

          filter_clause = filter_interpreter.build_query([filter].compact, from_field_path: filtering_field_path)

          inner_detail = yield

          return inner_detail if filter_clause.nil?
          key = "#{name}:filtered"

          clause = {
            key => {
              "filter" => filter_clause,
              "aggs" => inner_detail.clauses
            }.compact
          }

          inner_meta = inner_detail.meta
          meta =
            if (buckets_path = inner_detail.meta["buckets_path"])
              # In this case, we have some grouping aggregations applied, and the response will include a `buckets` array.
              # Here we are prefixing the `buckets_path` with the `key` used for our filter aggregation to maintain its accuracy.
              inner_meta.merge({"buckets_path" => [key] + buckets_path})
            else
              # In this case, no grouping aggregations have been applied, and the response will _not_ have a `buckets` array.
              # Instead, we'll need to treat the single unbucketed aggregation as a single bucket. To indicate that, we use
              # `bucket_path` (singular) rather than `buckets_path` (plural).
              inner_meta.merge({"bucket_path" => [key]})
            end

          AggregationDetail.new(clause, meta)
        end

        def computations_detail
          build_inner_aggregation_detail(computations) do |computation|
            {computation.key(aggregation_name: name) => computation.clause}
          end
        end

        def sub_aggregation_detail(filter_interpreter, parent_queries)
          build_inner_aggregation_detail(sub_aggregations.values) do |sub_agg|
            sub_agg.build_agg_hash(filter_interpreter, parent_queries: parent_queries)
          end
        end

        def build_inner_aggregation_detail(collection, &block)
          initial = {} # : ::Hash[::String, untyped]
          collection.map(&block).reduce(initial) do |accum, hash|
            Support::HashUtil.disjoint_merge(accum, hash)
          end
        end
      end

      # The details of an aggregation level, including the `aggs` clauses themselves and `meta`
      # that we want echoed back to us in the response for the aggregation level.
      AggregationDetail = ::Data.define(
        # Aggregation clauses that would go under `aggs.
        :clauses,
        # Custom metadata that will be echoed back to us in the response.
        # https://www.elastic.co/guide/en/elasticsearch/reference/8.11/search-aggregations.html#add-metadata-to-an-agg
        :meta
      ) do
        # @implements AggregationDetail

        # Wraps this aggregation detail in another aggregation layer for the given `grouping`,
        # so that we can easily build up the necessary multi-level aggregation structure.
        def wrap_with_grouping(grouping, query:)
          agg_key = grouping.key
          extra_inner_meta = grouping.inner_meta.merge({
            # The response just includes tuples of values for the key of each bucket. We need to know what fields those
            # values come from, and this `meta` field  indicates that.
            "grouping_fields" => [agg_key]
          })

          inner_agg_hash = {
            "aggs" => (clauses unless (clauses || {}).empty?),
            "meta" => meta.merge(extra_inner_meta)
          }.compact

          missing_bucket_inner_agg_hash = inner_agg_hash.key?("aggs") ? inner_agg_hash : {} # : ::Hash[::String, untyped]

          AggregationDetail.new(
            {
              agg_key => grouping.non_composite_clause_for(query).merge(inner_agg_hash),

              # Here we include a `missing` aggregation as a sibling to the main grouping aggregation. We do this
              # so that we get a bucket of documents that have `null` values for the field we are grouping on, in
              # order to provide the same behavior as the `CompositeGroupingAdapter` (which uses the built-in
              # `missing_bucket` option).
              #
              # To work correctly, we need to include this `missing` aggregation as a sibling at _every_ level of
              # the aggregation structure, and the `missing` aggregation needs the same child aggregations as the
              # main grouping aggregation has. Given the recursive nature of how this is applied, this results in
              # a fairly complex structure, even though conceptually the idea behind this isn't _too_ bad.
              Key.missing_value_bucket_key(agg_key) => {
                "missing" => {"field" => grouping.encoded_index_field_path}
              }.merge(missing_bucket_inner_agg_hash)
            },
            {"buckets_path" => [agg_key]}
          )
        end
      end
    end
  end
end
