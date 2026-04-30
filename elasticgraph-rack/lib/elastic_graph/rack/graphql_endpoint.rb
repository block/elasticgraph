# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphql/http_endpoint"
require "rack"

module ElasticGraph
  module Rack
    # A simple [Rack](https://github.com/rack/rack) wrapper around an ElasticGraph GraphQL endpoint.
    # This can be used for local development, mounted in a [Rails](https://rubyonrails.org/) application,
    # or run in any other Rack-compatible context.
    #
    # @example Simple config.ru to run an ElasticGraph endpoint as a Rack application
    #   require "elastic_graph/graphql"
    #   require "elastic_graph/rack/graphql_endpoint"
    #
    #   graphql = ElasticGraph::GraphQL.from_yaml_file("config/settings/development.yaml")
    #   run ElasticGraph::Rack::GraphQLEndpoint.new(graphql)
    class GraphQLEndpoint
      # @param graphql [ElasticGraph::GraphQL] ElasticGraph GraphQL instance
      # @param body_serializer [#call, nil] optional callable invoked with the GraphQL result
      #   hash; its return value is used as the response body. The body may be a `String` or
      #   any object responding to `each` per the Rack body spec. Use this to bypass the
      #   default `JSON.generate(result.to_h)` allocation — for example, by streaming the
      #   result hash directly into the response output stream via a JSON encoder of your
      #   choice. Errors and non-200 responses still produce a `String` body.
      def initialize(graphql, body_serializer: nil)
        @logger = graphql.logger
        @graphql_http_endpoint = graphql.graphql_http_endpoint
        @body_serializer = body_serializer
      end

      # Responds to a Rack request.
      #
      # @param env [Hash<String, Object>] Rack env
      # @return [Array(Integer, Hash<String, String>, #each)]
      def call(env)
        rack_request = ::Rack::Request.new(env)

        # Rack doesn't provide a nice method to provide all HTTP headers. In general,
        # HTTP headers are prefixed with `HTTP_` as per https://stackoverflow.com/a/6318491/16481862,
        # but `Content-Type`, as a "standard" header, isn't exposed that way, sadly.
        headers = env
          .select { |k, v| k.start_with?("HTTP_") }
          .to_h { |k, v| [k.delete_prefix("HTTP_"), v] }
          .merge("Content-Type" => rack_request.content_type)

        request = GraphQL::HTTPRequest.new(
          http_method: rack_request.request_method.downcase.to_sym,
          url: rack_request.url,
          headers: headers,
          body: rack_request.body&.read
        )

        response =
          if (body_serializer = @body_serializer)
            @graphql_http_endpoint.process(request, &body_serializer)
          else
            @graphql_http_endpoint.process(request)
          end

        body = response.body
        rack_body = body.is_a?(::String) ? [body] : body

        [response.status_code, response.headers.transform_keys(&:downcase), rack_body]
      rescue => e
        raise if ENV["RACK_ENV"] == "test"

        @logger.error "Got an exception: #{e.class.name}: #{e.message}\n\n#{e.backtrace.join("\n")}"
        error = {message: e.message, exception_class: e.class, backtrace: e.backtrace}
        [500, {"content-type" => "application/json"}, [::JSON.generate(errors: [error])]]
      end
    end
  end
end
