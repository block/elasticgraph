# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  class GraphQL
    # Class used to track details of what happens during a single GraphQL query for the purposes of logging.
    # Here we use `Struct` instead of `Data` specifically because it is designed to be mutable.
    class QueryDetailsTracker < Struct.new(
      :shard_routing_values,
      :search_index_expressions,
      :query_counts_per_datastore_request,
      :datastore_query_server_duration_ms,
      :datastore_query_client_duration_ms,
      :queried_shard_count,
      :mutex
    )
      def self.empty
        new(
          shard_routing_values: ::Set.new,
          search_index_expressions: ::Set.new,
          query_counts_per_datastore_request: [],
          datastore_query_server_duration_ms: 0,
          datastore_query_client_duration_ms: 0,
          queried_shard_count: 0,
          mutex: ::Thread::Mutex.new
        )
      end

      def record_datastore_queries_for_single_request(queries)
        mutex.synchronize do
          shard_routing_values.merge(queries.flat_map { |q| q.shard_routing_values || [] })
          search_index_expressions.merge(queries.map(&:search_index_expression))
          query_counts_per_datastore_request << queries.size
        end
      end

      def record_datastore_query_metrics(client_duration_ms:, server_duration_ms:, queried_shard_count:)
        mutex.synchronize do
          self.datastore_query_client_duration_ms += client_duration_ms
          self.datastore_query_server_duration_ms += server_duration_ms if server_duration_ms
          self.queried_shard_count += queried_shard_count
        end
      end

      # Indicates how long was spent on transport between the client and the datastore server, including
      # network time, JSON serialization time, etc.
      def datastore_request_transport_duration_ms
        datastore_query_client_duration_ms - datastore_query_server_duration_ms
      end
    end
  end
end
