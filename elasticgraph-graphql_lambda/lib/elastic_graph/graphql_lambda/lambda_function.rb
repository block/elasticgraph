# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/lambda_support/lambda_function"

module ElasticGraph
  module GraphQLLambda
    # @private
    class LambdaFunction
      prepend LambdaSupport::LambdaFunction

      def initialize
        require "elastic_graph/graphql_lambda"
        require "elastic_graph/graphql_lambda/graphql_endpoint"

        graphql = ElasticGraph::GraphQLLambda.graphql_from_env

        # ElasticGraph loads things lazily by default. We want to eagerly load
        # the graphql gem, the GraphQL schema, etc. rather than waiting for the
        # first request, since we want consistent response times.
        graphql.load_dependencies_eagerly

        @graphql_endpoint = ElasticGraph::GraphQLLambda::GraphQLEndpoint.new(graphql)
      end

      def handle_request(event:, context:)
        @graphql_endpoint.handle_request(event: event, context: context)
      end
    end
  end
end

# Lambda handler for `elasticgraph-graphql_lambda`.
ExecuteGraphQLQuery = ElasticGraph::GraphQLLambda::LambdaFunction.new
