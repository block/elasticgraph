# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/query_registry/query_validators/for_registered_client"
require "elastic_graph/query_registry/query_validators/for_unregistered_client"
require "graphql"
require "pathname"

module ElasticGraph
  module QueryRegistry
    # An abstraction that implements a registry of GraphQL queries. Callers should use
    # `build_and_validate_query` to get `GraphQL::Query` objects so that clients are properly
    # limited in what queries we execute on their behalf.
    #
    # Note that this class is designed to be as efficient as possible:
    #
    # - Registered GraphQL queries are only parsed once, and then the parsed form is used
    #   each time that query is submitted. In our benchmarking, parsing of large queries
    #   can be significant, taking ~10ms or so.
    # - We delay parsing a registered client's queries until the first time that client
    #   sends us a query. That way, we don't have to pay any parsing cost for queries
    #   that were registered by an old client that no longer sends us requests.
    # - Likewise, we defer reading a client's registered query strings off of disk until
    #   the first time it submits a request.
    #
    # In addition, it's worth noting that we support some basic "fuzzy" matching of query
    # strings, based on the query canonicalization performed by the GraphQL gem. Semantically
    # insignificant changes to the query string from a registered query (such as whitespace
    # differences, or comments) are tolerated.
    class Registry
      # Public factory method, which builds a `Registry` instance from the given directory.
      # Subdirectories are treated as client names, and the files in them are treated as
      # individually registered queries.
      def self.build_from_directory(schema, directory, allow_unregistered_clients:, allow_any_query_for_clients:, warn_on_unregistered_query_for_clients:, logger:)
        directory = Pathname.new(directory)

        new(
          schema,
          client_names: directory.children.map { |client_dir| client_dir.basename.to_s },
          allow_unregistered_clients: allow_unregistered_clients,
          allow_any_query_for_clients: allow_any_query_for_clients,
          warn_on_unregistered_query_for_clients: warn_on_unregistered_query_for_clients,
          logger: logger
        ) do |client_name|
          # Lazily read queries off of disk when we need to for a given client.
          (directory / client_name).glob("*.graphql").map { |file| ::File.read(file.to_s) }
        end
      end

      # Builds a `GraphQL::Query` object for the given query string, and validates that it is
      # an allowed query. Returns a list of registry validation errors in addition to the built
      # query object. The list of validation errors will be empty if the query should be allowed.
      # A query can be allowed either by virtue of being registered for usage by the given clent,
      # or by being for a completely unregistered client (if `allow_unregistered_clients` is `true`).
      #
      # This is also tolerant of some minimal differences in the query string (such as comments
      # and whitespace). If the query differs in a significant way from a registered query, it
      # will not be recognized as registered.
      def build_and_validate_query(query_string, client:, variables: {}, operation_name: nil, context: {})
        validator =
          if @registered_client_validator.applies_to?(client)
            @registered_client_validator
          else
            @unregistered_client_validator
          end

        validator.build_and_validate_query(query_string, client: client, variables: variables, operation_name: operation_name, context: context) do
          @schema.new_graphql_query(
            query_string,
            variables: variables,
            operation_name: operation_name,
            context: context
          )
        end
      end

      private

      def initialize(schema, client_names:, allow_unregistered_clients:, allow_any_query_for_clients:, warn_on_unregistered_query_for_clients:, logger:, &provide_query_strings_for_client)
        @schema = schema
        allow_any_query_for_clients_set = allow_any_query_for_clients.to_set
        warn_on_unregistered_query_for_clients_set = warn_on_unregistered_query_for_clients.to_set

        @registered_client_validator = QueryValidators::ForRegisteredClient.new(
          schema: schema,
          client_names: client_names,
          allow_any_query_for_clients: allow_any_query_for_clients_set,
          warn_on_unregistered_query_for_clients: warn_on_unregistered_query_for_clients_set,
          logger: logger,
          provide_query_strings_for_client: provide_query_strings_for_client
        )

        @unregistered_client_validator = QueryValidators::ForUnregisteredClient.new(
          allow_unregistered_clients: allow_unregistered_clients,
          allow_any_query_for_clients: allow_any_query_for_clients_set
        )
      end
    end
  end
end
