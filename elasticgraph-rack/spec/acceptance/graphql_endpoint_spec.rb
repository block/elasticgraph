# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/rack"
require "elastic_graph/rack/graphql_endpoint"
require "elastic_graph/constants"

module ElasticGraph::Rack
  RSpec.describe GraphQLEndpoint, :rack_app, :uses_datastore do
    let(:graphql) { build_graphql }
    let(:app_to_test) { GraphQLEndpoint.new(graphql) }

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

    it "exposes a GraphQL endpoint as a rack app" do
      response = call_graphql_query(introspection_query)

      expect(response.dig("data", "__schema", "types").count).to be > 5
    end

    it "supports executing queries submitted as a GET" do
      get "/?query=#{::URI.encode_www_form_component(introspection_query)}"

      expect(last_response.status).to eq 200
      expect(::JSON.parse(last_response.body).dig("data", "__schema", "types").count).to be > 5
    end

    it "respects the `#{ElasticGraph::TIMEOUT_MS_HEADER}` header, returning a 504 Gateway Timeout when a datastore query times out" do
      with_header ElasticGraph::TIMEOUT_MS_HEADER, "0" do
        expect {
          post_json "/", JSON.generate(query: <<~QUERY)
            query { widgets { edges { node { id } } } }
          QUERY
        }.to log_warning(a_string_including("ElasticGraph::Errors::RequestExceededDeadlineError"))
      end

      expect(last_response.status).to eq 504
      expect_json_error_including("Search exceeded requested timeout.")
    end

    it "returns a 400 if the `#{ElasticGraph::TIMEOUT_MS_HEADER}` header value is invalid" do
      with_header ElasticGraph::TIMEOUT_MS_HEADER, "zero" do
        post_json "/", JSON.generate(query: <<~QUERY)
          query { widgets { edges { node { id } } } }
        QUERY
      end

      expect(last_response.status).to eq 400
      expect_json_error_including(ElasticGraph::TIMEOUT_MS_HEADER, "zero", "invalid")
    end

    it "returns a 400 if the request body is not parseable JSON" do
      post_json "/", "not json"

      expect(last_response.status).to eq 400
      expect_json_error_including("invalid JSON")
    end

    it "responds reasonably if the request lacks a `query` field in the JSON" do
      expect {
        post_json "/", "{}"
      }.to log_warning(a_string_including("No query string"))

      expect(last_response.status).to eq 200
      expect_json_error_including("No query string")
    end

    context "when executing the query raises an exception" do
      before do
        allow(graphql.graphql_query_executor).to receive(:execute).and_raise("boom")
      end

      it "allows exceptions to be raised in the test environment" do
        with_env "RACK_ENV" => "test" do
          expect {
            call_graphql_query(introspection_query)
          }.to raise_error("boom")
        end
      end

      it "renders exceptions (instead of propagating them) in non-test environments" do
        with_env "RACK_ENV" => "development" do
          expect {
            post_json "/", JSON.generate(query: introspection_query)
          }.to log_warning(a_string_including("boom"))

          expect(last_response.status).to eq 500
          expect_json_error_including("boom")
        end
      end
    end

    def expect_json_error_including(*parts)
      expect(last_response.headers).to include("Content-Type" => "application/json")
      expect(::JSON.parse(last_response.body)).to include("errors" => [a_hash_including("message" => a_string_including(*parts))])
    end
  end
end
