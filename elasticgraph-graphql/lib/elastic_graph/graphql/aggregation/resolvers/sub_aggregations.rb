# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphql/aggregation/composite_grouping_adapter"
require "elastic_graph/graphql/aggregation/field_path_encoder"
require "elastic_graph/graphql/aggregation/key"
require "elastic_graph/graphql/aggregation/non_composite_grouping_adapter"
require "elastic_graph/graphql/aggregation/resolvers/count_detail"
require "elastic_graph/graphql/decoded_cursor"
require "elastic_graph/graphql/resolvers/resolvable_value"
require "elastic_graph/support/hash_util"

module ElasticGraph
  class GraphQL
    module Aggregation
      module Resolvers
        class SubAggregations < ::Data.define(:schema_element_names, :sub_aggregations, :parent_queries, :sub_aggs_by_agg_key, :field_path)
          def resolve(field:, object:, args:, context:, lookahead:)
            path_segment = PathSegment.for(field: field, lookahead: lookahead)
            new_field_path = field_path + [path_segment]
            return with(field_path: new_field_path) unless field.type.elasticgraph_category == :nested_sub_aggregation_connection

            sub_agg_key = FieldPathEncoder.encode(new_field_path.map(&:name_in_graphql_query))
            sub_agg_query = Support::HashUtil.verbose_fetch(sub_aggregations, sub_agg_key).query

            RelayConnectionBuilder.build_from_buckets(
              query: sub_agg_query,
              parent_queries: parent_queries,
              schema_element_names: schema_element_names,
              field_path: new_field_path
            ) { extract_buckets(sub_agg_key, args) }
          end

          private

          def extract_buckets(aggregation_field_path, args)
            # When the client passes `first: 0`, we omit the sub-aggregation from the query body entirely,
            # and it wont' be in `sub_aggs_by_agg_key`. Instead, we can just return an empty list of buckets.
            return [] if args[schema_element_names.first] == 0

            sub_agg_key = Key.encode(parent_queries.map(&:name) + [aggregation_field_path])
            sub_agg = Support::HashUtil.verbose_fetch(sub_aggs_by_agg_key, sub_agg_key)
            meta = sub_agg.fetch("meta")

            # When the sub-aggregation node of the GraphQL query has a `filter` argument, the direct sub-aggregation returned by
            # the datastore will be the unfiltered sub-aggregation. To get the filtered sub-aggregation (the data our client
            # actually cares about), we have a sub-aggregation under that.
            #
            # To indicate this case, our query includes a `meta` field which which tells us which sub-key # has the actual data we care about in it:
            # - If grouping has been applied (leading to multiple buckets): `meta: {buckets_path: [path, to, bucket]}`
            # - If no grouping has been applied (leading to a single bucket): `meta: {bucket_path: [path, to, bucket]}`
            if (buckets_path = meta["buckets_path"])
              bucket_adapter = BUCKET_ADAPTERS.fetch(sub_agg.dig("meta", "adapter"))
              bucket_adapter.prepare_response_buckets(sub_agg, buckets_path, meta)
            else
              singleton_bucket =
                if (bucket_path = meta["bucket_path"])
                  sub_agg.dig(*bucket_path)
                else
                  sub_agg
                end

              # When we have a single ungrouped bucket, we never have any error on the `doc_count`.
              # Our resolver logic expects it to be present, though.
              [singleton_bucket.merge({"doc_count_error_upper_bound" => 0})]
            end
          end

          BUCKET_ADAPTERS = [CompositeGroupingAdapter, NonCompositeGroupingAdapter].to_h do |adapter|
            [adapter.meta_name, adapter]
          end
        end
      end
    end
  end
end
