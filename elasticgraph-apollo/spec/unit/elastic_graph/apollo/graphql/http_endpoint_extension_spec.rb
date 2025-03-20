# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/apollo/graphql/engine_extension"
require "elastic_graph/apollo/graphql/http_endpoint_extension"
require "elastic_graph/graphql"
require "elastic_graph/graphql/http_endpoint"

module ElasticGraph
  module Apollo
    module GraphQL
      RSpec.describe HTTPEndpointExtension, :builds_graphql do
        let(:graphql) do
          build_graphql(
            schema_artifacts_directory: "config/schema/artifacts_with_apollo",
            extension_modules: [EngineExtension]
          )
        end

        let(:query) { "query { __typename }" }

        it "does not add Apollo tracing by default" do
          response_body = execute_expecting_no_errors(query)

          expect(response_body).to eq("data" => {"__typename" => "Query"})
        end

        it "adds Apollo tracing if the `Apollo-Federation-Include-Trace` header is set to `ftv1`, regardless of its casing" do
          r1 = execute_expecting_no_errors(query, headers: {"Apollo-Federation-Include-Trace" => "ftv1"})
          r2 = execute_expecting_no_errors(query, headers: {"Apollo_Federation_Include_Trace" => "ftv1"})
          r3 = execute_expecting_no_errors(query, headers: {"apollo-federation-include-trace" => "ftv1"})
          r4 = execute_expecting_no_errors(query, headers: {"apollo_federation_include_trace" => "ftv1"})
          r5 = execute_expecting_no_errors(query, headers: {"APOLLO-FEDERATION-INCLUDE-TRACE" => "ftv1"})
          r6 = execute_expecting_no_errors(query, headers: {"APOLLO_FEDERATION_INCLUDE_TRACE" => "ftv1"})

          expect([r1, r2, r3, r4, r5, r6]).to all match(
            "data" => {"__typename" => "Query"},
            "extensions" => {"ftv1" => /\w+/}
          )
        end

        it "does not add Apollo tracing if the `Apollo-Federation-Include-Trace` header is set another value, regardless of its casing" do
          response_body = execute_expecting_no_errors(query, headers: {"Apollo-Federation-Include-Trace" => "ftv2"})

          expect(response_body).to eq("data" => {"__typename" => "Query"})
        end

        def execute_expecting_no_errors(query, headers: {})
          request = ElasticGraph::GraphQL::HTTPRequest.new(
            http_method: :post,
            url: "/",
            headers: headers.merge("Content-Type" => "application/json"),
            body: ::JSON.generate("query" => query)
          )

          response = graphql.graphql_http_endpoint.process(request)
          expect(response.status_code).to eq(200)

          response_body = ::JSON.parse(response.body)
          expect(response_body["errors"]).to be nil
          response_body
        end
      end
    end
  end
end
