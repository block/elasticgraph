# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/query_interceptor/graphql_extension"
require "elastic_graph/graphql/http_endpoint"

module ElasticGraph
  module QueryInterceptor
    RSpec.describe GraphQLExtension, :in_temp_dir, :builds_graphql do
      let(:performed_datastore_queries) { [] }
      let(:router) { instance_double("ElasticGraph::GraphQL::DatastoreSearchRouter") }
      let(:interceptors) do
        [
          {
            "extension_name" => "MyApp::HideNonPublicThings",
            "require_path" => "./hide_non_public_things"
          },
          {
            "extension_name" => "MyApp::FilterOnUser",
            "require_path" => "./filter_on_user",
            "config" => {"header" => "USER-NAME", "key" => "user"}
          }
        ]
      end

      before do
        ::File.write("hide_non_public_things.rb", <<~EOS)
          module MyApp
            class HideNonPublicThings
              attr_reader :elasticgraph_graphql

              def initialize(elasticgraph_graphql:, config:)
                @elasticgraph_graphql = elasticgraph_graphql
              end

              def intercept(query, field:, args:, http_request:, context:)
                query.merge_with(filters: [{"public" => {"equal_to_any_of" => [false]}}])
              end
            end
          end
        EOS

        ::File.write("filter_on_user.rb", <<~EOS)
          module MyApp
            class FilterOnUser
              attr_reader :elasticgraph_graphql

              def initialize(elasticgraph_graphql:, config:)
                @elasticgraph_graphql = elasticgraph_graphql
                @config = config
              end

              def intercept(query, field:, args:, http_request:, context:)
                user_name = http_request.normalized_headers[@config.fetch("header")]
                query.merge_with(filters: [{@config.fetch("key") => {"equal_to_any_of" => [user_name]}}])
              end
            end
          end
        EOS

        allow(router).to receive(:msearch) do |queries|
          performed_datastore_queries.concat(queries)
          queries.to_h { |query| [query, GraphQL::DatastoreResponse::SearchResponse::EMPTY] }
        end
      end

      it "works end-to-end to allow the interceptors to add extra filters to the datastore query" do
        graphql = build_graphql(
          extension_modules: [GraphQLExtension],
          extension_settings: {"query_interceptor" => {"interceptors" => interceptors}},
          datastore_search_router: router
        )

        process(<<~EOS, graphql: graphql, headers: {"USER-NAME" => "yoda"})
          query {
            addresses {
              total_edge_count
            }
          }
        EOS

        expect(performed_datastore_queries.size).to eq(1)
        expect(performed_datastore_queries.first.filters).to contain_exactly(
          {"public" => {"equal_to_any_of" => [false]}},
          {"user" => {"equal_to_any_of" => ["yoda"]}}
        )

        expect_configured_interceptors(graphql) do
          [MyApp::HideNonPublicThings, MyApp::FilterOnUser]
        end
      end

      it "adds interceptors defined in runtime metadata" do
        schema_artifacts = generate_schema_artifacts do |schema|
          schema.register_graphql_extension(
            ElasticGraph::QueryInterceptor::GraphQLExtension,
            defined_at: "elastic_graph/query_interceptor/graphql_extension",
            interceptors: interceptors
          )
        end

        graphql = build_graphql(
          extension_modules: [GraphQLExtension],
          schema_artifacts: schema_artifacts
        )

        expect_configured_interceptors(graphql) do
          [MyApp::HideNonPublicThings, MyApp::FilterOnUser]
        end
      end

      it "does not add interceptors if GraphQLExtension is not used" do
        schema_artifacts = generate_schema_artifacts do |schema|
          schema.register_graphql_extension(
            Module.new,
            defined_at: __FILE__,
            interceptors: interceptors
          )
        end

        graphql = build_graphql(
          extension_modules: [GraphQLExtension],
          schema_artifacts: schema_artifacts
        )

        expect_configured_interceptors(graphql) { [] }
      end

      context "when the GraphQL extension has been registered on the schema with no specific interceptors" do
        it "still loads the interceptors from config" do
          schema_artifacts = generate_schema_artifacts do |schema|
            schema.register_graphql_extension(
              ElasticGraph::QueryInterceptor::GraphQLExtension,
              defined_at: "elastic_graph/query_interceptor/graphql_extension"
            )
          end

          graphql = build_graphql(
            schema_artifacts: schema_artifacts,
            extension_settings: {"query_interceptor" => {"interceptors" => interceptors}}
          )

          expect_configured_interceptors(graphql) do
            [MyApp::HideNonPublicThings, MyApp::FilterOnUser]
          end
        end
      end

      def process(query, graphql:, headers: {})
        headers = headers.merge("Content-Type" => "application/graphql")
        request = GraphQL::HTTPRequest.new(url: "http://foo.com/bar", http_method: :post, body: query, headers: headers)
        graphql.graphql_http_endpoint.process(request)
      end

      def expect_configured_interceptors(graphql)
        query_adapter = graphql.datastore_query_adapters.last
        expect(query_adapter).to be_a QueryInterceptor::DatastoreQueryAdapter
        expect(query_adapter.interceptors).to match_array(yield) # we yield to make it lazy since the interceptors are loaded lazily
        expect(query_adapter.interceptors.map(&:elasticgraph_graphql)).to all be graphql
      end

      def generate_schema_artifacts
        super do |schema|
          yield schema

          # Ensure there's at least one indexed type defined to avoid GraphQL validation errors.
          schema.object_type "Widget" do |t|
            t.field "id", "ID"
            t.index "widgets"
          end
        end
      end
    end
  end
end
