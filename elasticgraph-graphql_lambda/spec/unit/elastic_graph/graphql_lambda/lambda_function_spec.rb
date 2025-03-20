# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/spec_support/lambda_function"

RSpec.describe "GraphQL lambda function" do
  include_context "lambda function"

  # Doesn't matter which API Gateway version adapter we include here--we just need one of them.
  include ElasticGraph::GraphQLLambda::APIGatewayV2HTTPAPI

  it "executes GraphQL queries" do
    expect_loading_lambda_to_define_constant(
      lambda: "elastic_graph/graphql_lambda/lambda_function.rb",
      const: :ExecuteGraphQLQuery
    ) do |lambda_function|
      event = build_event(
        http_method: :post,
        path: "/graphql",
        body: "query { __typename }",
        headers: {"Content-Type" => "application/graphql"},
        user_arn: "arn:aws:iam::123456789012:user/username"
      )
      # AWS docs don't tell us what the class name is for the
      # `context` object, and we don't have it available to verify against, anyway. So we gotta use
      # a non-verifying double here. But https://docs.aws.amazon.com/lambda/latest/dg/ruby-context.html
      # documents the available methods on the context object.
      context = double("AWSLambdaContext", get_remaining_time_in_millis: 10_000) # standard:disable RSpec/VerifiedDoubles
      response = lambda_function.handle_request(event: event, context: context)

      expect(response.fetch(:statusCode)).to eq 200
      expect(::JSON.parse(response.fetch(:body))).to eq({"data" => {"__typename" => "Query"}})
    end
  end
end
