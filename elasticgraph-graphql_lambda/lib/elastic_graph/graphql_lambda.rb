# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphql"
require "elastic_graph/lambda_support"

module ElasticGraph
  # @private
  module GraphQLLambda
    # Builds an `ElasticGraph::GraphQL` instance from our lambda ENV vars.
    def self.graphql_from_env
      LambdaSupport.build_from_env(GraphQL)
    end
  end
end
