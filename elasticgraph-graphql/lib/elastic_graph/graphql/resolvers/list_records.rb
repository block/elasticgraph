# Copyright 2024 Block, Inc.
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
        def initialize(resolver_query_adapter:)
          @resolver_query_adapter = resolver_query_adapter
        end

        def call(parent_type, graphql_field, object, args, context)
          field = context.fetch(:elastic_graph_schema).field_named(parent_type.graphql_name, graphql_field.name)
          lookahead = args.fetch(:lookahead)
          args = field.args_to_schema_form(args.except(:lookahead))
          query = @resolver_query_adapter.build_query_from(field: field, args: args, lookahead: lookahead, context: context)
          response = QuerySource.execute_one(query, for_context: context)
          RelayConnection.maybe_wrap(response, field: field, context: context, lookahead: lookahead, query: query)
        end
      end
    end
  end
end
