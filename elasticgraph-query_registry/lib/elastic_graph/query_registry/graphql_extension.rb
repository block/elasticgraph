# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphql/query_executor"
require "elastic_graph/query_registry/registry"
require "graphql"
require "pathname"

module ElasticGraph
  module QueryRegistry
    module GraphQLExtension
      def graphql_query_executor
        @graphql_query_executor ||= begin
          registry_config = QueryRegistry::Config.from_parsed_yaml(config.extension_settings)

          RegistryAwareQueryExecutor.new(
            schema: schema,
            monotonic_clock: monotonic_clock,
            logger: logger,
            slow_query_threshold_ms: config.slow_query_latency_warning_threshold_in_ms,
            registry_directory: registry_config.path_to_registry,
            allow_unregistered_clients: registry_config.allow_unregistered_clients,
            allow_any_query_for_clients: registry_config.allow_any_query_for_clients
          )
        end
      end
    end

    class RegistryAwareQueryExecutor < GraphQL::QueryExecutor
      def initialize(
        registry_directory:,
        allow_unregistered_clients:,
        allow_any_query_for_clients:,
        schema:,
        monotonic_clock:,
        logger:,
        slow_query_threshold_ms:
      )
        super(
          schema: schema,
          monotonic_clock: monotonic_clock,
          logger: logger,
          slow_query_threshold_ms: slow_query_threshold_ms
        )

        @registry = Registry.build_from_directory(
          schema,
          registry_directory,
          allow_unregistered_clients: allow_unregistered_clients,
          allow_any_query_for_clients: allow_any_query_for_clients
        )
      end

      private

      def build_and_execute_query(query_string:, variables:, operation_name:, context:, client:)
        query, errors, query_registered = @registry.build_and_validate_query_with_registration_status(
          query_string,
          variables: variables,
          operation_name: operation_name,
          context: context,
          client: client
        )

        # Set the query_registered field in the query tracker
        query_tracker = context[:elastic_graph_query_tracker]
        query_tracker.set_extension_data("query_registered", query_registered.to_s)

        if errors.empty?
          [query, execute_query(query, client: client)]
        else
          result = ::GraphQL::Query::Result.new(
            query: nil,
            values: {"errors" => errors.map { |e| {"message" => e} }}
          )

          [query, result]
        end
      end
    end

    class Config < ::Data.define(:path_to_registry, :allow_unregistered_clients, :allow_any_query_for_clients)
      def self.from_parsed_yaml(hash)
        hash = hash.fetch("query_registry") { return DEFAULT }

        new(
          path_to_registry: hash.fetch("path_to_registry"),
          allow_unregistered_clients: hash.fetch("allow_unregistered_clients"),
          allow_any_query_for_clients: hash.fetch("allow_any_query_for_clients")
        )
      end

      DEFAULT = new(
        path_to_registry: (_ = __dir__),
        allow_unregistered_clients: true,
        allow_any_query_for_clients: []
      )
    end
  end
end
