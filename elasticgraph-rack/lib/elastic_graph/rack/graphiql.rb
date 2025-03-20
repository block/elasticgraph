# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/rack/graphql_endpoint"
require "rack/builder"
require "rack/static"

module ElasticGraph
  module Rack
    # A [Rack](https://github.com/rack/rack) application that serves both an ElasticGraph GraphQL endpoint
    # and a [GraphiQL IDE](https://github.com/graphql/graphiql). This can be used for local development,
    # mounted in a [Rails](https://rubyonrails.org/) application, or run in any other Rack-compatible context.
    #
    # @example Simple config.ru to run GraphiQL as a Rack application, targeting an ElasticGraph endpoint
    #   require "elastic_graph/graphql"
    #   require "elastic_graph/rack/graphiql"
    #
    #   graphql = ElasticGraph::GraphQL.from_yaml_file("config/settings/development.yaml")
    #   run ElasticGraph::Rack::GraphiQL.new(graphql)
    module GraphiQL
      # Builds a [Rack](https://github.com/rack/rack) application that serves both an ElasticGraph GraphQL endpoint
      # and a [GraphiQL IDE](https://github.com/graphql/graphiql).
      #
      # @param graphql [ElasticGraph::GraphQL] ElasticGraph GraphQL instance
      # @return [Rack::Builder] built Rack application
      def self.new(graphql)
        graphql_endpoint = ElasticGraph::Rack::GraphQLEndpoint.new(graphql)

        ::Rack::Builder.new do
          use ::Rack::Static, urls: {"/" => "index.html"}, root: ::File.join(__dir__, "graphiql")

          map "/graphql" do
            run graphql_endpoint
          end
        end
      end
    end
  end
end
