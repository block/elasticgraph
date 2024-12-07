# Copyright 2024 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphql/client"
require "elastic_graph/support/memoizable_data"
require "json"
require "uri"

module ElasticGraph
  class GraphQL
    # Handles HTTP concerns for when ElasticGraph is served via HTTP. The logic here
    # is based on the graphql.org recommendations:
    #
    # https://graphql.org/learn/serving-over-http/#http-methods-headers-and-body
    #
    # As that recommends, we support queries in 3 different HTTP forms:
    #
    # - A standard POST request as application/json with query/operationName/variables in the body.
    # - A GET request with `query`, `operationName` and `variables` query params in the URL.
    # - A POST as application/graphql with a query string in the body.
    #
    # Note that this is designed to be agnostic to what the calling HTTP context is (for example,
    # AWS Lambda, or Rails, or Rack...). Instead, this uses simple Request/Response value objects
    # that the calling context can easily translate to/from to use this in any HTTP context.
    class HTTPEndpoint
      APPLICATION_JSON = "application/json"
      APPLICATION_GRAPHQL = "application/graphql"

      def initialize(query_executor:, monotonic_clock:, client_resolver:)
        @query_executor = query_executor
        @monotonic_clock = monotonic_clock
        @client_resolver = client_resolver
      end

      # Processes the given HTTP request, returning an HTTP response.
      #
      # `max_timeout_in_ms` is not a property of the HTTP request (the
      # calling application will determine it instead!) so it is a separate argument.
      #
      # Note that this method does _not_ convert exceptions to 500 responses. It's up to
      # the calling application to do that if it wants to (and to determine how much of the
      # exception to return in the HTTP response...).
      def process(request, max_timeout_in_ms: nil, start_time_in_ms: @monotonic_clock.now_in_ms)
        client_or_response = @client_resolver.resolve(request)
        return client_or_response if client_or_response.is_a?(HTTPResponse)

        with_parsed_request(request, max_timeout_in_ms: max_timeout_in_ms) do |parsed|
          result = @query_executor.execute(
            parsed.query_string,
            variables: parsed.variables,
            operation_name: parsed.operation_name,
            client: client_or_response,
            timeout_in_ms: parsed.timeout_in_ms,
            context: parsed.context,
            start_time_in_ms: start_time_in_ms
          )

          HTTPResponse.json(200, result.to_h)
        end
      rescue Errors::RequestExceededDeadlineError
        HTTPResponse.error(504, "Search exceeded requested timeout.")
      end

      private

      # Helper method that converts `HTTPRequest` to a parsed form we can work with.
      # If the request can be successfully parsed, a `ParsedRequest` will be yielded;
      # otherwise an `HTTPResponse` will be returned with an error.
      def with_parsed_request(request, max_timeout_in_ms:)
        with_request_params(request) do |params|
          with_timeout(request, max_timeout_in_ms: max_timeout_in_ms) do |timeout_in_ms|
            with_context(request) do |context|
              yield ParsedRequest.new(
                query_string: params["query"],
                variables: params["variables"] || {},
                operation_name: params["operationName"],
                timeout_in_ms: timeout_in_ms,
                context: context
              )
            end
          end
        end
      end

      # Responsible for handling the 3 types of requests we need to handle:
      #
      # - A standard POST request as application/json with query/operationName/variables in the body.
      # - A GET request with `query`, `operationName` and `variables` query params in the URL.
      # - A POST as application/graphql with a query string in the body.
      #
      # This yields a hash containing the query/operationName/variables if successful; otherwise
      # it returns an `HTTPResponse` with an error.
      def with_request_params(request)
        params =
          # POST with application/json is the most common form requests take, so we have it as the first branch here.
          if request.http_method == :post && request.content_type == APPLICATION_JSON
            begin
              ::JSON.parse(request.body.to_s)
            rescue ::JSON::ParserError
              # standard:disable Lint/NoReturnInBeginEndBlocks
              return HTTPResponse.error(400, "Request body is invalid JSON.")
              # standard:enable Lint/NoReturnInBeginEndBlocks
            end

          elsif request.http_method == :post && request.content_type == APPLICATION_GRAPHQL
            {"query" => request.body}

          elsif request.http_method == :post
            return HTTPResponse.error(415, "`#{request.content_type}` is not a supported content type. Only `#{APPLICATION_JSON}` and `#{APPLICATION_GRAPHQL}` are supported.")

          elsif request.http_method == :get
            ::URI.decode_www_form(::URI.parse(request.url).query.to_s).to_h.tap do |hash|
              # Variables must come in as JSON, even if in the URL. express-graphql does it this way,
              # which is a bit of a canonical implementation, as it is referenced from graphql.org:
              # https://github.com/graphql/express-graphql/blob/v0.12.0/src/index.ts#L492-L497
              hash["variables"] &&= ::JSON.parse(hash["variables"])
            rescue ::JSON::ParserError
              return HTTPResponse.error(400, "Variables are invalid JSON.")
            end

          else
            return HTTPResponse.error(405, "GraphQL only supports GET and POST requests.")
          end

        # Ignore an empty string operationName.
        params = params.merge("operationName" => nil) if params["operationName"] && params["operationName"].empty?

        if (variables = params["variables"]) && !variables.is_a?(::Hash)
          return HTTPResponse.error(400, "`variables` must be a JSON object but was not.")
        end

        yield params
      end

      # Responsible for figuring out the timeout, based on a header and a provided max.
      # If successful, yields the timeout value; otherwise will return an `HTTPResponse` with
      # an error.
      def with_timeout(request, max_timeout_in_ms:)
        requested_timeout_in_ms =
          if (timeout_in_ms_str = request.normalized_headers[HTTPRequest.normalize_header_name(TIMEOUT_MS_HEADER)])
            begin
              Integer(timeout_in_ms_str)
            rescue ::ArgumentError
              # standard:disable Lint/NoReturnInBeginEndBlocks
              return HTTPResponse.error(400, "`#{TIMEOUT_MS_HEADER}` header value of #{timeout_in_ms_str.inspect} is invalid")
              # standard:enable Lint/NoReturnInBeginEndBlocks
            end
          end

        yield [max_timeout_in_ms, requested_timeout_in_ms].compact.min
      end

      # Responsible for determining any `context` values to pass down into the `query_executor`,
      # which in turn will make the values available to the GraphQL resolvers.
      #
      # By default, our only context value is the HTTP request. This method exists to provide an extension
      # point so that ElasticGraph extensions can add `context` values based on the `request` as desired.
      #
      # Extensions can return an `HTTPResponse` with an error if the `request` is invalid according
      # to their requirements. Otherwise, they must call `super` (to delegate to this and any other
      # extensions) with a block. In the block, they must merge in their `context` values and then `yield`.
      def with_context(request)
        yield({http_request: request})
      end

      ParsedRequest = Data.define(:query_string, :variables, :operation_name, :timeout_in_ms, :context)
    end

    # Represents an HTTP request, containing:
    #
    # - http_method: a symbol like :get or :post.
    # - url: a string containing the full URL.
    # - headers: a hash with string keys and values containing HTTP headers. The headers can
    #   be in any form like `Content-Type`, `content-type`, `CONTENT-TYPE`, `CONTENT_TYPE`, etc.
    # - body: a string containing the request body, if there was one.
    HTTPRequest = Support::MemoizableData.define(:http_method, :url, :headers, :body) do
      # @implements HTTPRequest

      # HTTP headers are intended to be case-insensitive, and different Web frameworks treat them differently.
      # For example, Rack uppercases them with `_` in place of `-`.  With AWS Lambda proxy integrations API
      # gateway HTTP APIs, header names are lowercased:
      # https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api-develop-integrations-lambda.html
      #
      # ...but for integration with API gateway REST APIs, header names are provided as-is:
      # https://docs.aws.amazon.com/apigateway/latest/developerguide/set-up-lambda-proxy-integrations.html#api-gateway-simple-proxy-for-lambda-input-format
      #
      # To be maximally compatible here, this normalizes to uppercase form with dashes in place of underscores.
      def normalized_headers
        @normalized_headers ||= headers.transform_keys do |key|
          HTTPRequest.normalize_header_name(key)
        end
      end

      def content_type
        normalized_headers["CONTENT-TYPE"]
      end

      def self.normalize_header_name(header)
        header.upcase.tr("_", "-")
      end
    end

    # Represents an HTTP response, containing:
    #
    # - status_code: an integer like 200.
    # - headers: a hash with string keys and values containing HTTP response headers.
    # - body: a string containing the response body.
    HTTPResponse = Data.define(:status_code, :headers, :body) do
      # @implements HTTPResponse

      # Helper method for building a JSON response.
      def self.json(status_code, body)
        new(status_code, {"Content-Type" => HTTPEndpoint::APPLICATION_JSON}, ::JSON.generate(body))
      end

      # Helper method for building an error response.
      def self.error(status_code, message)
        json(status_code, {"errors" => [{"message" => message}]})
      end
    end

    # Steep weirdly expects them here...
    # @dynamic initialize, config, logger, runtime_metadata, graphql_schema_string, datastore_core, clock
    # @dynamic graphql_http_endpoint, graphql_query_executor, schema, datastore_search_router, filter_interpreter, filter_node_interpreter
    # @dynamic datastore_query_builder, graphql_gem_plugins, graphql_resolvers, datastore_query_adapters, monotonic_clock
    # @dynamic load_dependencies_eagerly, self.from_parsed_yaml, filter_args_translator, sub_aggregation_grouping_adapter
  end
end
