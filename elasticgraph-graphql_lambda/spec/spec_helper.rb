# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

# This file is contains RSpec configuration and common support code for `elasticgraph-graphql_lambda`.
# Note that it gets loaded by `spec_support/spec_helper.rb` which contains common spec support
# code for all ElasticGraph test suites.

module ElasticGraph
  module GraphQLLambda
    # https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api-develop-integrations-lambda.html#1.0
    module APIGatewayV1HTTPAPI
      def build_event(http_method:, path:, body:, headers:, user_arn:, request_context: {})
        uri = URI(path)

        # Note: this isn't the entire event; it's just the fields we care about. See link above for a full example.
        {
          "version" => "1.0",
          "resource" => uri.path,
          "path" => uri.path,
          "httpMethod" => http_method.to_s.upcase,
          "headers" => headers.transform_keys(&:downcase),
          "multiValueHeaders" => headers.transform_keys(&:downcase).transform_values { |v| [v] },
          "queryStringParameters" => ::URI.decode_www_form(uri.query.to_s).to_h,
          "multiValueQueryStringParameters" => ::URI.decode_www_form(uri.query.to_s).to_h.transform_values { |v| [v] },
          "requestContext" => {
            "httpMethod" => http_method.to_s.upcase,
            "path" => uri.path,
            "protocol" => "HTTP/1.1",
            "resourcePath" => uri.path,
            "identity" => {
              "userArn" => user_arn
            }
          }.merge(request_context),
          "body" => body,
          "isBase64Encoded" => false
        }
      end
    end

    # https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api-develop-integrations-lambda.html#2.0
    module APIGatewayV2HTTPAPI
      def build_event(http_method:, path:, body:, headers:, user_arn:, request_context: {})
        uri = URI(path)

        # Note: this isn't the entire event; it's just the fields we care about. See link above for a full example.
        # Note also that `userArn` isn't anywhere in this payload :(.
        {
          "version" => "2.0",
          "rawPath" => uri.path,
          "rawQueryString" => uri.query,
          "headers" => headers.transform_keys(&:downcase),
          "queryStringParameters" => ::URI.decode_www_form(uri.query.to_s).to_h,
          "requestContext" => {
            "http" => {
              "method" => http_method.to_s.upcase,
              "path" => uri.path,
              "protocol" => "HTTP/1.1"
            },
            "stage" => "test-stage"
          }.merge(request_context),
          "body" => body,
          "isBase64Encoded" => false
        }
      end
    end

    # https://docs.aws.amazon.com/apigateway/latest/developerguide/set-up-lambda-proxy-integrations.html#api-gateway-simple-proxy-for-lambda-input-format
    module APIGatewayRestAPI
      def build_event(http_method:, path:, body:, headers:, user_arn:, request_context: {})
        uri = URI(path)

        # Note: this isn't the entire event; it's just the fields we care about. See link above for a full example.
        {
          "resource" => uri.path,
          "path" => uri.path,
          "httpMethod" => http_method.to_s.upcase,
          "headers" => headers.transform_keys(&:downcase),
          "multiValueHeaders" => headers.transform_keys(&:downcase).transform_values { |v| [v] },
          "queryStringParameters" => ::URI.decode_www_form(uri.query.to_s).to_h,
          "multiValueQueryStringParameters" => ::URI.decode_www_form(uri.query.to_s).to_h.transform_values { |v| [v] },
          "requestContext" => {
            "httpMethod" => http_method.to_s.upcase,
            "path" => uri.path,
            "protocol" => "HTTP/1.1",
            "resourcePath" => uri.path,
            "identity" => {
              "userArn" => user_arn
            },
            "stage" => "test-stage"
          }.merge(request_context),
          "body" => body,
          "isBase64Encoded" => false
        }
      end
    end
  end
end
