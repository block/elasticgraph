# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/constants"
require "elastic_graph/graphql"
require "uri"

module ElasticGraph
  module GraphQLLambda
    # @private
    class GraphQLEndpoint
      # Used to add a timeout buffer so that the lambda timeout should generally not be reached,
      # instead preferring our `timeout_in_ms` behavior to the harsher timeout imposed by lambda itself.
      # We prefer this in order to have consistent timeout behavior, regardless of what timeout is
      # reached. For example, we have designed our timeout logic to disconnect from the datastore
      # (which causes it to kill the running query) but we do not know if the lambda-based timeout
      # would also cause that. This buffer gives our lambda enough time to respond before the hard
      # lambda timeout so that it should (hopefully) never get reached.
      #
      # Note we generally run with a 30 second overall lambda timeout so a single second of buffer
      # still gives plenty of time to satisfy the query.
      LAMBDA_TIMEOUT_BUFFER_MS = 1_000

      # As per https://docs.aws.amazon.com/lambda/latest/dg/gettingstarted-limits.html, AWS Lambdas
      # are limited to returning up to 6 MB responses.
      #
      # Note: 6 MB is technically 6291456 bytes, but the AWS log message when you exceed the limit mentions
      # a limit of 6291556 (100 bytes larger!). Here we use the smaller threshold since it's the documented value.
      LAMBDA_MAX_RESPONSE_PAYLOAD_BYTES = (_ = 2**20) * 6

      def initialize(graphql)
        @graphql_http_endpoint = graphql.graphql_http_endpoint
        @logger = graphql.logger
        @monotonic_clock = graphql.monotonic_clock
      end

      def handle_request(event:, context:)
        start_time_in_ms = @monotonic_clock.now_in_ms # should be the first line so our duration logging is accurate
        request = request_from(event)

        response = @graphql_http_endpoint.process(
          request,
          max_timeout_in_ms: context.get_remaining_time_in_millis - LAMBDA_TIMEOUT_BUFFER_MS,
          start_time_in_ms: start_time_in_ms
        )

        convert_response(response)
      end

      private

      def request_from(event)
        # The `GRAPHQL_LAMBDA_AWS_ARN_HEADER` header can be used to determine who the client is, which
        # has security implications. Therefore, we need to make sure it can't be spoofed. Here we remove
        # any header which, when normalized, is equivalent to that header.
        headers = event.fetch("headers").reject do |key, _|
          GraphQL::HTTPRequest.normalize_header_name(key) == GRAPHQL_LAMBDA_AWS_ARN_HEADER
        end

        header_overrides = {
          GRAPHQL_LAMBDA_AWS_ARN_HEADER => event.dig("requestContext", "identity", "userArn")
        }.compact

        GraphQL::HTTPRequest.new(
          url: url_from(event),
          http_method: http_method_from(event),
          headers: headers.merge(header_overrides),
          body: event.fetch("body")
        )
      end

      def convert_response(response)
        if response.body.bytesize >= LAMBDA_MAX_RESPONSE_PAYLOAD_BYTES
          response = content_too_large_response(response)
        end

        {statusCode: response.status_code, body: response.body, headers: response.headers}
      end

      def url_from(event)
        uri = URI.join("/")

        # stage_name will be part of the path when a client tries to send a request to an API Gateway endpoint
        # but will be omitted from the path in the actual event. For example a call to <domain-name>/stage-name/graphql
        # will be passed in the event as `requestContext.stage` = "stage-name" and `path` = "/graphql". Here we are
        # using stage_name to be placed back in as a prefix for the path.
        # Note: stage is not expected to ever be nil or empty when invoked through API Gateway. Here we handle that case
        #       to be tolerant of it but we don't expect it to ever happen.
        #
        # The event format can be seen here: https://docs.aws.amazon.com/apigateway/latest/developerguide/set-up-lambda-proxy-integrations.html#api-gateway-simple-proxy-for-lambda-input-format
        # As you should be able to see, the stage name isn't included in the path. In this doc
        # https://docs.aws.amazon.com/apigateway/latest/developerguide/how-to-call-api.html you should be able to see that stage_name is included in the
        # base url for invoking a REST API.
        stage_name = event.dig("requestContext", "stage") || ""
        stage_name = "/" + stage_name unless stage_name == ""

        # It'll be `path` if it's an HTTP API with a v1.0 payload:
        # https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api-develop-integrations-lambda.html#1.0
        #
        # And for a REST API, it'll also be `path`:
        # https://docs.aws.amazon.com/apigateway/latest/developerguide/set-up-lambda-proxy-integrations.html#api-gateway-simple-proxy-for-lambda-input-format
        uri.path = stage_name + event.fetch("path") do
          # It'll be `rawPath` if it's an HTTP API with a v2.0 payload:
          # https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api-develop-integrations-lambda.html#2.0
          event.fetch("rawPath")
        end

        # If it's an HTTP API with a v2.0 payload, it'll have `rawQueryString`, which we want to use if available:
        # https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api-develop-integrations-lambda.html#2.0
        uri.query = event.fetch("rawQueryString") do
          # If it's an HTTP API with a v1.0 payload, it'll have `queryStringParameters` as a hash:
          # https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api-develop-integrations-lambda.html#1.0
          #
          # And for a REST API, it'll also have `queryStringParameters`:
          # https://docs.aws.amazon.com/apigateway/latest/developerguide/set-up-lambda-proxy-integrations.html#api-gateway-simple-proxy-for-lambda-input-format
          event.fetch("queryStringParameters")&.then { |params| ::URI.encode_www_form(params) }
        end

        uri.to_s
      end

      def http_method_from(event)
        # It'll be `httpMethod` if it's an HTTP API with a v1.0 payload:
        # https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api-develop-integrations-lambda.html#1.0
        #
        # And for a REST API, it'll also be `httpMethod`:
        # https://docs.aws.amazon.com/apigateway/latest/developerguide/set-up-lambda-proxy-integrations.html#api-gateway-simple-proxy-for-lambda-input-format
        event.fetch("httpMethod") do
          # Unfortunately, for an HTTP API with a v2.0 payload, the method is only available from `requestContext.http.method`:
          # https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api-develop-integrations-lambda.html#2.0
          event.fetch("requestContext").fetch("http").fetch("method")
        end.downcase.to_sym
      end

      # Responsible for building a response when the existing response is too large to
      # return due to AWS Lambda response size limits.
      #
      # Note: an HTTP 413 status code[^1] would usually be appropriate, but we're not
      # totally sure how API gateway will treat that (e.g. will it pass the response
      # body through to the client?) and the GraphQL-over-HTTP spec recommends[^2] that
      # we return a 200 in this case:
      #
      # > This section only applies when the response body is to use the
      # > `application/json` media type.
      # >
      # > The server SHOULD use the `200` status code for every response to a well-formed
      # > _GraphQL-over-HTTP request_, independent of any _GraphQL request error_ or
      # > _GraphQL field error_ raised.
      # >
      # > Note: A status code in the `4xx` or `5xx` ranges or status code `203` (and maybe
      # > others) could originate from intermediary servers; since the client cannot
      # > determine if an `application/json` response with arbitrary status code is a
      # > well-formed _GraphQL response_ (because it cannot trust the source) the server
      # > must use `200` status code to guarantee to the client that the response has not
      # > been generated or modified by an intermediary.
      # >
      # > ...
      # > The server SHOULD NOT use a `4xx` or `5xx` status code for a response to a
      # > well-formed _GraphQL-over-HTTP request_.
      # >
      # > Note: For compatibility with legacy servers, this specification allows the use
      # > of `4xx` or `5xx` status codes for a failed well-formed _GraphQL-over-HTTP
      # > request_ where the response uses the `application/json` media type, but it is
      # > strongly discouraged. To use `4xx` and `5xx` status codes in these situations,
      # > please use the `application/graphql-response+json` media type.
      #
      # At the time of this writing, ElasticGraph uses the `application/json` media type.
      # We may want to migrate to `application/graphql-response+json` at some later point,
      # at which time we can consider using 413 instead.
      #
      # [^1]: https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/413
      # [^2]: https://github.com/graphql/graphql-over-http/blob/4db4e501f0537a14fd324c455294056676e38e8c/spec/GraphQLOverHTTP.md#applicationjson
      def content_too_large_response(response)
        GraphQL::HTTPResponse.json(200, {
          "errors" => [{
            "message" => "The query results were #{response.body.bytesize} bytes, which exceeds the max AWS Lambda response size (#{LAMBDA_MAX_RESPONSE_PAYLOAD_BYTES} bytes). Please update the query to request less data and try again."
          }]
        })
      end
    end
  end
end
