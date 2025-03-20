# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphql/resolvers/query_source"
require "elastic_graph/graphql/resolvers/relay_connection"

module ElasticGraph
  class GraphQL
    module Resolvers
      # Responsible for fetching a a list of records of a particular type
      class ListRecords
        def initialize(elasticgraph_graphql:, config:)
          # Nothing to initialize, but needs to be defined to satisfy the resolver interface.
        end

        def resolve(field:, object:, args:, context:, lookahead:)
          query = yield
          response = QuerySource.execute_one(query, for_context: context)
          RelayConnection.maybe_wrap(response, field: field, context: context, lookahead: lookahead, query: query)
        end
      end
    end
  end
end
