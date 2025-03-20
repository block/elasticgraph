# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphql/aggregation/resolvers/aggregated_values"
require "elastic_graph/graphql/aggregation/resolvers/grouped_by"
require "elastic_graph/graphql/decoded_cursor"
require "elastic_graph/graphql/resolvers/resolvable_value"

module ElasticGraph
  class GraphQL
    module Aggregation
      module Resolvers
        class Node < GraphQL::Resolvers::ResolvableValue.new(:query, :parent_queries, :bucket, :field_path)
          # This file defines a subclass of `Node` and can't be loaded until `Node` has been defined.
          require "elastic_graph/graphql/aggregation/resolvers/sub_aggregations"

          def grouped_by
            @grouped_by ||= GroupedBy.new(bucket, field_path)
          end

          def aggregated_values
            @aggregated_values ||= AggregatedValues.new(query.name, bucket, field_path)
          end

          def sub_aggregations
            @sub_aggregations ||= SubAggregations.new(
              schema_element_names,
              query.sub_aggregations,
              parent_queries + [query],
              bucket,
              field_path
            )
          end

          def count
            bucket.fetch("doc_count")
          end

          def count_detail
            @count_detail ||= CountDetail.new(schema_element_names, bucket)
          end

          def cursor
            # If there's no `key`, then we aren't grouping by anything. We just have a single aggregation
            # bucket containing computed values over the entire set of filtered documents. In that case,
            # we still need a pagination cursor but we have no "key" to speak of that we can encode. Instead,
            # we use the special SINGLETON cursor defined for this case.
            @cursor ||=
              if (key = bucket.fetch("key")).empty?
                DecodedCursor::SINGLETON
              else
                DecodedCursor.new(key)
              end
          end
        end
      end
    end
  end
end
