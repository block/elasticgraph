# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/constants"
require "elastic_graph/graphql_lambda/graphql_endpoint"
require "elastic_graph/support/hash_util"
require "json"
require "uri"

module ElasticGraph
  module GraphQLLambda
    RSpec.describe GraphQLEndpoint, :builds_graphql do
      shared_examples_for "HTTP handling" do |supports_user_arn: true, supports_get: true|
        let(:graphql) { build_graphql }
        let(:endpoint) { GraphQLEndpoint.new(graphql) }
        let(:processed_requests) { [] }

        let(:introspection_query) do
          <<~IQUERY
            query IntrospectionQuery {
              __schema {
                types {
                  kind
                  name
                }
              }
            }
          IQUERY
        end

        before do
          allow(graphql.graphql_http_endpoint).to receive(:process).and_wrap_original do |original, request, **options|
            processed_requests << request
            original.call(request, **options)
          end
        end

        it "processes the provided GraphQL query" do
          response = handle_request(body: JSON.generate("query" => introspection_query))

          expect(response).to include(statusCode: 200, body: a_hash_including("data"))
        end

        context "when the response payload exceeds the AWS Lambda max response size" do
          it "returns a clear error to avoid manifesting as a confusing API gateway failure" do
            stub_const("#{GraphQLEndpoint.name}::LAMBDA_MAX_RESPONSE_PAYLOAD_BYTES", 10)

            response = handle_request(body: JSON.generate("query" => introspection_query))

            expect(response).to include(statusCode: 200)
            expect(::JSON.parse(response[:body]).dig("errors", 0, "message")).to match(/The query results were \d+ bytes, which exceeds the max AWS Lambda response size \(10 bytes\)/)
          end
        end

        if supports_get
          it "supports executing queries submitted as a GET" do
            response = handle_request(http_method: :get, path: "/?query=#{::URI.encode_www_form_component(introspection_query)}")

            expect(response).to include(statusCode: 200, body: a_hash_including("data"))
          end
        end

        it "respects the `#{TIMEOUT_MS_HEADER}` header, regardless of casing, returning a 504 Gateway Timeout when a datastore query times out" do
          response = handle_widget_query_request_with_headers({TIMEOUT_MS_HEADER => "0"})
          expect_json_error_including(response, 504, "Search exceeded requested timeout.")

          response = handle_widget_query_request_with_headers({TIMEOUT_MS_HEADER.downcase => "0"})
          expect_json_error_including(response, 504, "Search exceeded requested timeout.")

          response = handle_widget_query_request_with_headers({TIMEOUT_MS_HEADER.upcase => "0"})
          expect_json_error_including(response, 504, "Search exceeded requested timeout.")
        end

        it "passes a `max_timeout_in_ms` based on `context.get_remaining_time_in_millis`" do
          timeout = max_timeout_used_for(lambda_time_remaining_ms: 15_400)

          expect(timeout).to eq(15_400 - GraphQLEndpoint::LAMBDA_TIMEOUT_BUFFER_MS)
        end

        it "returns a 400 if the timeout header is not formatted correctly" do
          response = handle_widget_query_request_with_headers({TIMEOUT_MS_HEADER => "zero"})

          expect_json_error_including(response, 400, TIMEOUT_MS_HEADER, "zero", "invalid")
        end

        it "returns a 400 if the request body is not valid JSON" do
          response = handle_request(body: "not json")

          expect_json_error_including(response, 400, "is invalid JSON")
        end

        it "responds reasonably if the request lacks a `query` field in the JSON" do
          response = handle_request(body: "{}")

          expect_json_error_including(response, 200, "No query string")
        end

        if supports_user_arn
          it "passes the `#{GRAPHQL_LAMBDA_AWS_ARN_HEADER}` HTTP header so the configured client resolver can use it" do
            user_arn = "arn:aws:sts::123456789:role/client_app"
            headers = effective_http_headers_for_query(user_arn: user_arn)

            expect(headers).to include(GRAPHQL_LAMBDA_AWS_ARN_HEADER => user_arn)
          end

          it "overwrites a `#{GRAPHQL_LAMBDA_AWS_ARN_HEADER}` HTTP header passed by the client so that clients can't spoof it" do
            user_arn = "arn:aws:sts::123456789:role/client_app"
            headers = effective_http_headers_for_query(
              user_arn: user_arn,
              headers: {
                GRAPHQL_LAMBDA_AWS_ARN_HEADER => "arn:aws:sts::123456789:role/attacker",
                GRAPHQL_LAMBDA_AWS_ARN_HEADER.downcase => "arn:aws:sts::123456789:role/attacker",
                GRAPHQL_LAMBDA_AWS_ARN_HEADER.tr("-", "_") => "arn:aws:sts::123456789:role/attacker",
                GRAPHQL_LAMBDA_AWS_ARN_HEADER.downcase.tr("-", "_") => "arn:aws:sts::123456789:role/attacker"
              }
            )

            expect(headers.except("content-type")).to eq({GRAPHQL_LAMBDA_AWS_ARN_HEADER => user_arn})
          end
        else
          it "passes no value for the `#{GRAPHQL_LAMBDA_AWS_ARN_HEADER}` HTTP header since no value is available" do
            headers = effective_http_headers_for_query(user_arn: nil)

            expect(headers).to exclude(GRAPHQL_LAMBDA_AWS_ARN_HEADER)
          end

          it "drops a `#{GRAPHQL_LAMBDA_AWS_ARN_HEADER}` HTTP header passed by the client so that clients can't spoof it" do
            headers = effective_http_headers_for_query(
              user_arn: nil,
              headers: {
                GRAPHQL_LAMBDA_AWS_ARN_HEADER => "arn:aws:sts::123456789:role/attacker",
                GRAPHQL_LAMBDA_AWS_ARN_HEADER.downcase => "arn:aws:sts::123456789:role/attacker",
                GRAPHQL_LAMBDA_AWS_ARN_HEADER.tr("-", "_") => "arn:aws:sts::123456789:role/attacker",
                GRAPHQL_LAMBDA_AWS_ARN_HEADER.downcase.tr("-", "_") => "arn:aws:sts::123456789:role/attacker"
              }
            )

            expect(headers.except("content-type")).to eq({})
          end
        end

        def max_timeout_used_for(**options)
          used_timeout = nil

          allow(graphql.graphql_http_endpoint).to receive(:process).and_wrap_original do |original, request, **opts|
            used_timeout = opts[:max_timeout_in_ms]
            original.call(request, **opts)
          end

          handle_request(body: JSON.generate("query" => introspection_query), **options)

          used_timeout
        end

        def handle_widget_query_request_with_headers(headers)
          body = JSON.generate("query" => "query { widgets { edges { node { id } } } }")
          handle_request(body: body, headers: headers)
        end

        def handle_request(
          http_method: :post,
          path: "/",
          body: nil,
          headers: {},
          user_arn: "arn:aws:sts::123456789:assumed-role/someone",
          lambda_time_remaining_ms: 30_000,
          endpoint: self.endpoint,
          request_context: {}
        )
          event = build_event(
            http_method: http_method,
            path: path,
            body: body,
            headers: headers.merge("Content-Type" => "application/json"),
            user_arn: user_arn,
            request_context: request_context
          )

          # AWS docs don't tell us what the class name is for the
          # `context` object, and we don't have it available to verify against, anyway. So we gotta use
          # a non-verifying double here. But https://docs.aws.amazon.com/lambda/latest/dg/ruby-context.html
          # documents the available methods on the context object.
          context = double("AWSLambdaContext", get_remaining_time_in_millis: lambda_time_remaining_ms) # standard:disable RSpec/VerifiedDoubles

          endpoint.handle_request(event: event, context: context)
        end

        def expect_json_error_including(response, status_code, *parts)
          expect(response).to include(statusCode: status_code)
          expect(response[:headers]).to include("Content-Type" => "application/json")
          expect(::JSON.parse(response[:body])).to include("errors" => [a_hash_including("message" => a_string_including(*parts))])
        end

        def effective_http_headers_for_query(user_arn:, headers: {})
          effective_headers = nil

          allow(graphql.graphql_http_endpoint).to receive(:process).and_wrap_original do |original, request, **options|
            effective_headers = request.headers
            original.call(request, **options)
          end

          handle_request(body: JSON.generate("query" => introspection_query), user_arn: user_arn, headers: headers)

          effective_headers
        end
      end

      describe "an API Gateway HTTP API with the v1.0 payload format" do
        include APIGatewayV1HTTPAPI

        context "with query params" do
          include_examples "HTTP handling"
        end

        context "with no query params" do
          include_examples "HTTP handling", supports_get: false

          def build_event(...)
            super(...).merge("queryStringParameters" => nil, "multiValueQueryStringParameters" => nil)
          end

          after do
            bad_requests = processed_requests.select { |r| r.url == "/?" }
            expect(bad_requests).to be_empty, "Expected no requests to have a URL like `/?` but some did: #{bad_requests.inspect}"
          end
        end
      end

      describe "an API Gateway HTTP API with the v2.0 payload format" do
        include APIGatewayV2HTTPAPI

        context "with query params" do
          include_examples "HTTP handling", supports_user_arn: false
        end

        context "with no query params" do
          include_examples "HTTP handling", supports_user_arn: false, supports_get: false

          def build_event(...)
            super(...).merge("queryStringParameters" => nil)
          end

          after do
            bad_requests = processed_requests.select { |r| r.url == "/?" }
            expect(bad_requests).to be_empty, "Expected no requests to have a URL like `/?` but some did: #{bad_requests.inspect}"
          end
        end
      end

      describe "an API Gateway REST API with query params" do
        include APIGatewayRestAPI

        context "with query params" do
          include_examples "HTTP handling"
        end

        context "with no query params" do
          include_examples "HTTP handling", supports_get: false

          def build_event(...)
            super(...).merge("queryStringParameters" => nil)
          end

          after do
            bad_requests = processed_requests.select { |r| r.url == "/?" }
            expect(bad_requests).to be_empty, "Expected no requests to have a URL like `/?` but some did: #{bad_requests.inspect}"
          end
        end
      end
    end
  end
end
