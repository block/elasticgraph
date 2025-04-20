# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphql/client"
require "elastic_graph/query_registry/client_data"
require "graphql"

module ElasticGraph
  module QueryRegistry
    module QueryValidators
      # Query validator implementation used for registered clients.
      class ForRegisteredClient < ::Data.define(
        :schema,
        :allow_any_query_for_clients,
        :client_data_by_client_name,
        :client_cache_mutex,
        :provide_query_strings_for_client
      )
        def initialize(schema:, client_names:, allow_any_query_for_clients:, provide_query_strings_for_client:)
          super(
            schema: schema,
            allow_any_query_for_clients: allow_any_query_for_clients,
            client_cache_mutex: ::Mutex.new,
            provide_query_strings_for_client: provide_query_strings_for_client,
            client_data_by_client_name: client_names.to_h { |name| [name, nil] }.merge(
              # Register a built-in GraphQL query that ElasticGraph itself sometimes has to make.
              GraphQL::Client::ELASTICGRAPH_INTERNAL.name => ClientData.from(schema, [GraphQL::EAGER_LOAD_QUERY])
            )
          )
        end

        def applies_to?(client)
          return false unless (client_name = client&.name)
          client_data_by_client_name.key?(client_name)
        end

        def build_and_validate_query(query_string, client:, variables: {}, operation_name: nil, context: {})
          client_data = client_data_for(client.name)

          if (cached_query = client_data.cached_query_for(query_string.to_s))
            prepared_query = prepare_query_for_execution(cached_query, variables: variables, operation_name: operation_name, context: context)
            return [prepared_query, []]
          end

          query = yield

          # This client allows any query, so we can just return the query with no errors here.
          # Note: we could put this at the top of the method, but if the query is registered and matches
          # the registered form, the `cached_query` above is more efficient as it avoids unnecessarily
          # parsing the query.
          return [query, []] if allow_any_query_for_clients.include?(client.name)

          if !client_data.canonical_query_strings.include?(ClientData.canonical_query_string_from(query, schema_element_names: schema.element_names))
            return [query, [client_data.unregistered_query_error_for(query, client)]]
          end

          # The query is slightly different from a registered query, but not in any material fashion
          # (such as a whitespace or comment difference). Since query parsing can be kinda slow on
          # large queries (in our benchmarking, ~10ms on a 10KB query), we want to cache the parsed
          # query here. Normally, if a client sends a slightly different form of a query, it's going
          # to be in that alternate form every single time, so caching it can be a nice win.
          atomically_update_cached_client_data_for(client.name) do |cached_client_data|
            # We don't want the cached form of the query to persist the current variables, context, etc being used for this request.
            cachable_query = prepare_query_for_execution(query, variables: {}, operation_name: nil, context: {})

            # We use `_` here because Steep believes `client_data` could be nil. In general, this is
            # true; it can be nil, but not at this callsite, because we are in a branch that is only
            # executed when `client_data` is _not_ nil.
            (_ = cached_client_data).with_updated_last_query(query_string, cachable_query)
          end

          [query, []]
        end

        private

        def client_data_for(client_name)
          if (client_data = client_data_by_client_name[client_name])
            client_data
          else
            atomically_update_cached_client_data_for(client_name) do |cached_data|
              # We expect `cached_data` to be nil if we get here. However, it's technically possible for it
              # not to be. If this `client_data_for` method was called with the same client from another thread
              # in between the `client_data` fetch above and here, `cached_data` could not be populated.
              # In that case, we don't want to pay the expense of re-building `ClientData` for no reason.
              cached_data || ClientData.from(schema, provide_query_strings_for_client.call(client_name))
            end
          end
        end

        # Atomically updates the `ClientData` for the given `client_name`. All updates to our cache MUST go
        # through this method to ensure there are no concurrency-related bugs. The caller should pass
        # a block which will be yielded the current value in the cache (which can be `nil` initially); the
        # block is then responsible for returning an updated copy of `ClientData` in the state that
        # should be stored in the cache.
        def atomically_update_cached_client_data_for(client_name)
          client_cache_mutex.synchronize do
            client_data_by_client_name[client_name] = yield client_data_by_client_name[client_name]
          end
        end

        def prepare_query_for_execution(query, variables:, operation_name:, context:)
          schema.new_graphql_query(
            # Here we pass `document` instead of query string, so that we don't have to re-parse the query.
            # However, when the document is nil, we still need to pass the query string.
            query.document ? nil : query.query_string,
            document: query.document,
            variables: variables,
            operation_name: operation_name,
            context: context
          )
        end
      end
    end
  end
end
