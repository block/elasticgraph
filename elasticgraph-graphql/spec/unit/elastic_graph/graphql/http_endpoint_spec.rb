# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphql/datastore_response/search_response"
require "elastic_graph/graphql/http_endpoint"
require "support/client_resolvers"
require "uri"

module ElasticGraph
  class GraphQL
    RSpec.describe HTTPEndpoint do
      let(:router) { instance_double("ElasticGraph::GraphQL::DatastoreSearchRouter") }
      let(:monotonic_clock) { instance_double("ElasticGraph::Support::MonotonicClock", now_in_ms: 0) }
      let(:graphql) do
        build_graphql(
          datastore_search_router: router,
          monotonic_clock: monotonic_clock,
          client_resolver: ClientResolvers::ViaHTTPHeader.new({"header_name" => "X-CLIENT-NAME"})
        )
      end
      let(:expected_query_time) { 100 }
      let(:datastore_queries) { [] }
      let(:default_query) { "query { addresses { total_edge_count } }" }

      before do
        allow(router).to receive(:msearch) do |queries|
          if queries.any? { |q| q.monotonic_clock_deadline&.<(expected_query_time) }
            raise Errors::RequestExceededDeadlineError, "took too long"
          end

          datastore_queries.concat(queries)
          queries.to_h { |query| [query, DatastoreResponse::SearchResponse::EMPTY] }
        end
      end

      shared_examples_for "HTTP processing" do |only_query_string: false|
        it "can process a request given no `variables` or `operationName`" do
          response_body = process_graphql_expecting(200, query: "query { widgets { __typename } }")

          expect(response_body).to eq("data" => {"widgets" => {"__typename" => "WidgetConnection"}})
        end

        it "passes along the resolved client" do
          client = Client.new(name: "Bob", source_description: "X-CLIENT-NAME")

          expect(submitted_value_for(:client, extra_headers: {"X-CLIENT-NAME" => "Bob"})).to eq(client)
        end

        it "responds with the HTTP response returned by the client resolver if it returns one instead of a client so it can halt processing" do
          process_graphql_expecting(401, extra_headers: {"X-CLIENT-RESOLVER-RESPOND-WITH" => "401"})
        end

        context "when an graphql extension hooks into the HTTPEndpoint" do
          let(:graphql) do
            adapter = Class.new do
              def call(query:, context:, **)
                user_name = context.fetch(:http_request).normalized_headers["USER-NAME"]
                query.merge_with(filters: [{"user_name" => {"equal_to_any_of" => [user_name]}}])
              end
            end.new

            extension = Module.new do
              def graphql_http_endpoint
                @graphql_http_endpoint ||= super.tap do |endpoint|
                  endpoint.extend(Module.new do
                    def with_context(request)
                      super do |context|
                        yield context.merge(color: request.normalized_headers["COLOR"])
                      end
                    end
                  end)
                end
              end

              define_method :datastore_query_adapters do
                super() + [adapter]
              end
            end

            build_graphql(
              datastore_search_router: router,
              monotonic_clock: monotonic_clock,
              extension_modules: [extension]
            )
          end

          it "can customize the `context` passed down into the GraphQL resolvers" do
            expect(submitted_value_for(:context)).to include(color: nil)
            expect(submitted_value_for(:context, extra_headers: {"COLOR" => "red"})).to include(color: "red")
          end

          it "provides access to the HTTP request in the datastore query adapters, allowing the extension to change the query based on header values" do
            process_graphql_expecting(200, extra_headers: {"USER-NAME" => "yoda"})

            expect(datastore_queries.size).to eq 1
            expect(datastore_queries.first.filters).to contain_exactly(
              {"user_name" => {"equal_to_any_of" => ["yoda"]}}
            )
          end
        end

        it "respects the passed `#{TIMEOUT_MS_HEADER} header, regardless of its casing" do
          process_expecting_success_with_timeout_header_named = ->(header_name) do
            process_graphql_expecting(200, extra_headers: {header_name => expected_query_time + 1})
          end

          expect(TIMEOUT_MS_HEADER).to eq("ElasticGraph-Request-Timeout-Ms")
          process_expecting_success_with_timeout_header_named.call("ElasticGraph-Request-Timeout-Ms")
          process_expecting_success_with_timeout_header_named.call("elasticgraph-request-timeout-ms")
          process_expecting_success_with_timeout_header_named.call("ELASTICGRAPH-REQUEST-TIMEOUT-MS")
          process_expecting_success_with_timeout_header_named.call("ElasticGraph_Request_Timeout_Ms")
          process_expecting_success_with_timeout_header_named.call("elasticgraph_request_timeout_ms")
          process_expecting_success_with_timeout_header_named.call("ELASTICGRAPH_REQUEST_TIMEOUT_MS")

          expect(datastore_queries.size).to eq(6)
          expect(datastore_queries.map(&:monotonic_clock_deadline)).to all eq(expected_query_time + 1)
        end

        it "returns a 400 if the `#{TIMEOUT_MS_HEADER}` header value is invalid" do
          response_body = process_graphql_expecting(400, extra_headers: {TIMEOUT_MS_HEADER => "twelve"})

          expect(response_body).to eq error_with("`#{TIMEOUT_MS_HEADER}` header value of \"twelve\" is invalid")
        end

        it "returns a 504 Gateway Timeout when a datastore query times out" do
          response_body = process_graphql_expecting(504, extra_headers: {TIMEOUT_MS_HEADER => (expected_query_time - 1).to_s})

          expect(response_body).to eq error_with("Search exceeded requested timeout.")
        end

        context "when `max_timeout_in_ms` is passed" do
          it "uses that as the timeout if no `#{TIMEOUT_MS_HEADER}` header is passed" do
            process_graphql_expecting(200, max_timeout_in_ms: 12000)

            expect(datastore_queries.map(&:monotonic_clock_deadline)).to eq [12000]
          end

          it "uses the passed `#{TIMEOUT_MS_HEADER}` header value if it is less than the max" do
            process_graphql_expecting(200, max_timeout_in_ms: 12000, extra_headers: {TIMEOUT_MS_HEADER => "11999"})

            expect(datastore_queries.map(&:monotonic_clock_deadline)).to eq [11999]
          end

          it "uses that as the timeout if the passed `#{TIMEOUT_MS_HEADER}` header value exceeds the max" do
            process_graphql_expecting(200, max_timeout_in_ms: 12000, extra_headers: {TIMEOUT_MS_HEADER => "12001"})

            expect(datastore_queries.map(&:monotonic_clock_deadline)).to eq [12000]
          end
        end

        unless only_query_string
          it "ignores `operationName` if set to an empty string" do
            response_body = process_graphql_expecting(200, query: "query { widgets { __typename } }", operation_name: "")

            expect(response_body).to eq("data" => {"widgets" => {"__typename" => "WidgetConnection"}})
          end

          it "can select an operation to run using `operationName` when given a multi-operation query" do
            query = <<~EOS
              query Widgets { widgets { __typename } }
              query Components { components { __typename } }
            EOS

            response_body = process_graphql_expecting(200, query: query, operation_name: "Widgets")
            expect(response_body).to eq("data" => {"widgets" => {"__typename" => "WidgetConnection"}})

            response_body = process_graphql_expecting(200, query: query, operation_name: "Components")
            expect(response_body).to eq("data" => {"components" => {"__typename" => "ComponentConnection"}})
          end

          it "supports variables" do
            query = <<~EOS
              query Count($filter: WidgetFilterInput) {
                widgets(filter: $filter) {
                  total_edge_count
                }
              }
            EOS

            filter = {"id" => {"equal_to_any_of" => ["1"]}}

            response_body = process_graphql_expecting(200, query: query, variables: {"filter" => filter})
            expect(response_body).to eq("data" => {"widgets" => {"total_edge_count" => 0}})
            expect(datastore_queries.size).to eq(1)
            expect(datastore_queries.first.filters.to_a).to eq [filter]
          end

          it "returns a 400 response when the variables are not a JSON object" do
            query = "query Multiply($operands: Operands!) { multiply(operands: $operands) }"
            response = process_graphql_expecting(400, query: query, variables: "not a JSON object")

            expect(response).to eq error_with("`variables` must be a JSON object but was not.")
          end
        end

        def submitted_value_for(option_name, ...)
          submitted_value = nil

          query_executor = graphql.graphql_query_executor
          allow(query_executor).to receive(:execute).and_wrap_original do |original, query_string, **options|
            submitted_value = options[option_name]
            original.call(query_string, **options)
          end

          process_graphql_expecting(200, ...)
          submitted_value
        end
      end

      context "when given an application/json POST request" do
        include_examples "HTTP processing"

        it "returns a 400 response when the body is not parsable JSON" do
          response = process_expecting(400, body: "not json")

          expect(response).to eq error_with("Request body is invalid JSON.")
        end

        it "tolerates the Content-Type being in different forms (e.g. upper vs lower case)" do
          r1 = process_graphql_expecting(200, query: "query { widgets { __typename } }", headers: {"Content-Type" => "application/json"})
          r2 = process_graphql_expecting(200, query: "query { widgets { __typename } }", headers: {"content-type" => "application/json"})
          r3 = process_graphql_expecting(200, query: "query { widgets { __typename } }", headers: {"content_type" => "application/json"})
          r4 = process_graphql_expecting(200, query: "query { widgets { __typename } }", headers: {"CONTENT_TYPE" => "application/json"})
          r5 = process_graphql_expecting(200, query: "query { widgets { __typename } }", headers: {"CONTENT-TYPE" => "application/json"})

          expect([r1, r2, r3, r4, r5]).to all eq("data" => {"widgets" => {"__typename" => "WidgetConnection"}})
        end

        def process_graphql_expecting(status_code, query: default_query, variables: nil, operation_name: nil, **options)
          body = ::JSON.generate({
            "query" => query,
            "variables" => variables,
            "operationName" => operation_name
          }.compact)

          process_expecting(status_code, body: body, **options)
        end

        def process(headers: {"Content-Type" => "application/json"}, **options)
          super(http_method: :post, headers: headers, **options)
        end
      end

      context "when given an application/graphql POST request" do
        include_examples "HTTP processing", only_query_string: true

        def process_graphql_expecting(status_code, query: default_query, **options)
          process_expecting(status_code, body: query, **options)
        end

        def process(headers: {"Content-Type" => "application/graphql"}, **options)
          super(http_method: :post, headers: headers, **options)
        end
      end

      context "when given a GET request with query params" do
        include_examples "HTTP processing"

        it "returns a 400 response when the variables are not parsable JSON" do
          query_params = {
            "query" => "query Multiply($operands: Operands!) { multiply(operands: $operands) }",
            "variables" => "not a json string",
            "operationName" => "Multiply"
          }

          response = process_expecting(400, query_params: query_params)

          expect(response).to eq error_with("Variables are invalid JSON.")
        end

        it "handles a request with no query params" do
          response = process_expecting(200)

          expect(response).to eq error_with("No query string was present")
        end

        def process_graphql_expecting(status_code, query: default_query, variables: nil, operation_name: nil, headers: {}, **options)
          query_params = {
            "query" => query,
            "variables" => variables&.then { |v| ::JSON.generate(v) },
            "operationName" => operation_name
          }.compact

          process_expecting(status_code, query_params: query_params, http_method: :get, headers: headers, **options)
        end

        def process(query_params: {}, **options)
          query = ::URI.encode_www_form(query_params)
          super(http_method: :get, url: "http://foo.com/bar?#{query}", **options)
        end
      end

      it "returns a 415 when the request is a POST with an unsupported content type" do
        body = ::JSON.generate("query" => "query { widgets { __typename } }")
        response = process_expecting(415, http_method: :post, body: body, headers: {"Content-Type" => "text/json"})

        expect(response).to eq error_with("`text/json` is not a supported content type. Only `application/json` and `application/graphql` are supported.")
      end

      it "returns a 405 when the request is not a GET or POST" do
        r1 = process_expecting(405, http_method: :delete)
        r2 = process_expecting(405, http_method: :put)
        r3 = process_expecting(405, http_method: :options)
        r4 = process_expecting(405, http_method: :patch)
        r5 = process_expecting(405, http_method: :head)

        expect([r1, r2, r3, r4, r5]).to all eq error_with("GraphQL only supports GET and POST requests.")
      end

      it "returns an error when given a GET request with no query params" do
        response = process_expecting(200, http_method: :get, url: "http://foo.test/no/query/params")

        expect(response).to eq error_with("No query string was present")
      end

      def process_expecting(status_code, ...)
        response = process(...)

        expect(response.status_code).to eq(status_code)
        expect(response.headers).to include("Content-Type" => "application/json")

        ::JSON.parse(response.body)
      end

      def process(http_method:, url: "http://foo.test/bar", body: nil, headers: {}, extra_headers: {}, **options)
        request = HTTPRequest.new(url: url, http_method: http_method, body: body, headers: headers.merge(extra_headers))
        graphql.graphql_http_endpoint.process(request, **options)
      end

      def error_with(message)
        {"errors" => [{"message" => message}]}
      end
    end
  end
end
