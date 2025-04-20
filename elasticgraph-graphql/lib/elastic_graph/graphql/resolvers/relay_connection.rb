# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphql/aggregation/resolvers/relay_connection_builder"
require "elastic_graph/graphql/resolvers/relay_connection/search_response_adapter_builder"
require "elastic_graph/support/hash_util"

module ElasticGraph
  class GraphQL
    module Resolvers
      # Defines resolver logic related to relay connections. The relay connections spec is here:
      # https://facebook.github.io/relay/graphql/connections.htm
      module RelayConnection
        # Conditionally wraps the given search response in the appropriate relay connection adapter, if needed.
        def self.maybe_wrap(search_response, field:, context:, lookahead:, query:)
          return search_response unless field.type.relay_connection?

          schema_element_names = context.fetch(:elastic_graph_schema).element_names

          unless field.type.unwrap_fully.indexed_aggregation?
            return SearchResponseAdapterBuilder.build_from(
              schema_element_names: schema_element_names,
              search_response: search_response,
              query: query
            )
          end

          agg_name = lookahead.ast_nodes.first&.alias || lookahead.name
          Aggregation::Resolvers::RelayConnectionBuilder.build_from_search_response(
            schema_element_names: schema_element_names,
            search_response: search_response,
            query: Support::HashUtil.verbose_fetch(query.aggregations, agg_name)
          )
        end
      end
    end
  end
end
