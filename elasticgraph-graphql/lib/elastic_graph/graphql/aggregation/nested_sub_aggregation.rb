# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphql/aggregation/field_path_encoder"
require "elastic_graph/support/memoizable_data"

module ElasticGraph
  class GraphQL
    module Aggregation
      # Represents a sub-aggregation on a `nested` field.
      # For the relevant Elasticsearch docs, see:
      # https://www.elastic.co/guide/en/elasticsearch/reference/8.10/search-aggregations-bucket-nested-aggregation.html
      class NestedSubAggregation < Support::MemoizableData.define(:nested_path, :query)
        # The nested path in the GraphQL query from the parent aggregation to this-subaggregation, encoded
        # for use as a hash key.
        #
        # This key will be unique in the scope of the parent aggregation query, and thus suitable as a key
        # in a sub-aggregations hash.
        def nested_path_key
          @nested_path_key ||= FieldPathEncoder.encode(nested_path.map(&:name_in_graphql_query))
        end

        def build_agg_hash(filter_interpreter, parent_queries:)
          detail = query.build_agg_detail(filter_interpreter, field_path: nested_path, parent_queries: parent_queries, nested: true)
          return {} if detail.nil?

          parent_query_names = parent_queries.map(&:name)
          {
            Key.encode(parent_query_names + [nested_path_key]) => {
              "nested" => {"path" => FieldPathEncoder.encode(nested_path.filter_map(&:name_in_index))},
              "aggs" => detail.clauses,
              "meta" => detail.meta.merge({
                "size" => query.paginator.desired_page_size,
                "adapter" => query.grouping_adapter.meta_name
              })
            }.compact
          }
        end
      end
    end
  end
end
