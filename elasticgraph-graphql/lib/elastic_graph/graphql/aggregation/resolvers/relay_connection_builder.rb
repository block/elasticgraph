# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphql/aggregation/resolvers/node"
require "elastic_graph/graphql/datastore_query"
require "elastic_graph/graphql/resolvers/relay_connection/generic_adapter"

module ElasticGraph
  class GraphQL
    module Aggregation
      module Resolvers
        module RelayConnectionBuilder
          def self.build_from_search_response(query:, search_response:, schema_element_names:)
            build_from_buckets(query: query, parent_queries: [], schema_element_names: schema_element_names) do
              extract_buckets_from(search_response, for_query: query)
            end
          end

          def self.build_from_buckets(query:, parent_queries:, schema_element_names:, field_path: [], &build_buckets)
            GraphQL::Resolvers::RelayConnection::GenericAdapter.new(
              schema_element_names: schema_element_names,
              raw_nodes: raw_nodes_for(query, parent_queries, schema_element_names, field_path, &build_buckets),
              paginator: query.paginator,
              get_total_edge_count: -> {},
              to_sort_value: ->(node, decoded_cursor) do
                query.groupings.map do |grouping|
                  DatastoreQuery::Paginator::SortValue.new(
                    from_item: (_ = node).bucket.fetch("key").fetch(grouping.key),
                    from_cursor: decoded_cursor.sort_values.fetch(grouping.key),
                    sort_direction: :asc # we don't yet support any alternate sorting.
                  )
                end
              end
            )
          end

          private_class_method def self.raw_nodes_for(query, parent_queries, schema_element_names, field_path)
            # The `DecodedCursor::SINGLETON` is a special case, so handle it here.
            return [] if query.paginator.paginated_from_singleton_cursor?

            yield.map do |bucket|
              Node.new(
                schema_element_names: schema_element_names,
                query: query,
                parent_queries: parent_queries,
                bucket: bucket,
                field_path: field_path
              )
            end
          end

          private_class_method def self.extract_buckets_from(search_response, for_query:)
            search_response.raw_data.dig(
              "aggregations",
              for_query.name,
              "buckets"
            ) || [build_bucket(for_query, search_response.raw_data)]
          end

          private_class_method def self.build_bucket(query, response)
            defaults = {
              "key" => query.groupings.to_h { |g| [g.key, nil] },
              "doc_count" => response.dig("hits", "total", "value") || 0
            }

            empty_bucket_computations = query.computations.to_h do |computation|
              [computation.key(aggregation_name: query.name), {"value" => computation.detail.empty_bucket_value}]
            end

            defaults
              .merge(empty_bucket_computations)
              .merge(response["aggregations"] || {})
          end
        end
      end
    end
  end
end
