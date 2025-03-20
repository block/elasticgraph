# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphql/resolvers/relay_connection/search_response_adapter_builder"
require "support/sort"

module ElasticGraph
  class GraphQL
    module Resolvers
      module RelayConnection
        RSpec.describe SearchResponseAdapterBuilder do
          include SortSupport

          let(:decoded_cursor_factory) { decoded_cursor_factory_for("amount_cents") }

          attr_accessor :schema_artifacts

          before(:context) do
            self.schema_artifacts = generate_schema_artifacts do |schema|
              schema.object_type "Widget" do |t|
                t.field "id", "ID!"
                t.field "amount_cents", "Int!"
                t.index "widgets" do |i|
                  i.default_sort "amount_cents", :asc
                end
              end
            end
          end

          it "adapts the documents in a datastore search response to the relay connections edges interface" do
            results = execute_query(query: <<~QUERY, hits: [hit_for(300, "w1"), hit_for(400, "w2"), hit_for(500, "w3")])
              query {
                widgets {
                  edges {
                    cursor
                    node {
                      amount_cents
                    }
                  }
                }
              }
            QUERY

            expect(results).to match(
              "data" => {
                "widgets" => {
                  "edges" => [
                    edge_for(300, "w1"),
                    edge_for(400, "w2"),
                    edge_for(500, "w3")
                  ]
                }
              }
            )
          end

          it "exposes all of the page info fields defined in the relay 5.0 spec" do
            results = execute_query(query: <<~QUERY, hits: [hit_for(300, "w1"), hit_for(400, "w2"), hit_for(500, "w3")])
              query {
                widgets {
                  page_info {
                    has_previous_page
                    has_next_page
                    start_cursor
                    end_cursor
                  }
                }
              }
            QUERY

            expect(results).to match(
              "data" => {
                "widgets" => {
                  "page_info" => {
                    "has_previous_page" => a_boolean,
                    "has_next_page" => a_boolean,
                    "start_cursor" => decoded_cursor_factory.build([300, "w1"]).encode,
                    "end_cursor" => decoded_cursor_factory.build([500, "w3"]).encode
                  }
                }
              }
            )
          end

          it "supports `nodes` being used instead of `edges`" do
            results = execute_query(query: <<~QUERY, hits: [hit_for(300, "w1"), hit_for(400, "w2"), hit_for(500, "w3")])
              query {
                widgets {
                  nodes {
                    amount_cents
                  }
                }
              }
            QUERY

            expect(results).to match(
              "data" => {
                "widgets" => {
                  "nodes" => [
                    {"amount_cents" => 300},
                    {"amount_cents" => 400},
                    {"amount_cents" => 500}
                  ]
                }
              }
            )
          end

          # Note: the Relay 5.0 spec states `start_cursor`/`end_cursor` MUST be non-nullable:
          # https://github.com/facebook/relay/blob/v5.0.0/website/spec/Connections.md#fields-2
          # However, in practice, they must be null when `edges` is empty, and relay itself
          # implements this:
          # https://github.com/facebook/relay/commit/a17b462b3ff7355df4858a42ddda75f58c161302
          # Hopefully this PR will get merged fixing the spec:
          # https://github.com/facebook/relay/pull/2655
          it "exposes `null` for `start_cursor`/`end_cursor` when there are no hits" do
            results = execute_query(query: <<~QUERY, hits: [])
              query {
                widgets {
                  page_info {
                    start_cursor
                    end_cursor
                  }
                }
              }
            QUERY

            expect(results).to eq(
              "data" => {
                "widgets" => {
                  "page_info" => {
                    "start_cursor" => nil,
                    "end_cursor" => nil
                  }
                }
              }
            )
          end

          it "exposes the same cursor value for `start_cursor`/`end_cursor` when there is only one hit" do
            results = execute_query(query: <<~QUERY, hits: [hit_for(300, "w1")])
              query {
                widgets {
                  page_info {
                    start_cursor
                    end_cursor
                  }
                }
              }
            QUERY

            expected_cursor = decoded_cursor_factory.build([300, "w1"]).encode

            expect(results).to eq(
              "data" => {
                "widgets" => {
                  "page_info" => {
                    "start_cursor" => expected_cursor,
                    "end_cursor" => expected_cursor
                  }
                }
              }
            )
          end

          it "also exposes `total_edge_count` off of the connection even though it is not part of the relay connections spec" do
            results = execute_query(query: <<~QUERY, hits: [])
              query {
                widgets {
                  total_edge_count
                }
              }
            QUERY

            expect(results).to eq(
              "data" => {
                "widgets" => {
                  "total_edge_count" => 5
                }
              }
            )
          end

          def build_response_hash(hits)
            {
              "took" => 50,
              "timed_out" => false,
              "_shards" => {
                "total" => 5,
                "successful" => 5,
                "skipped" => 0,
                "failed" => 0
              },
              "hits" => {
                "total" => {
                  "value" => 5,
                  "relation" => "eq"
                },
                "max_score" => nil,
                "hits" => hits
              }
            }
          end

          def execute_query(query:, hits:)
            raw_data = build_response_hash(hits)
            datastore_client = stubbed_datastore_client(msearch: {"responses" => [raw_data]})
            graphql = build_graphql(schema_artifacts: schema_artifacts, clients_by_name: {"main" => datastore_client})

            graphql.graphql_query_executor.execute(query).to_h
          end

          def edge_for(amount_cents, id)
            {
              "cursor" => decoded_cursor_factory.build([amount_cents, id]).encode,
              "node" => {"amount_cents" => amount_cents}
            }
          end

          def hit_for(amount_cents, id)
            {
              "_index" => "widgets",
              "_type" => "_doc",
              "_id" => id,
              "_score" => nil,
              "_source" => {
                "id" => id,
                "version" => 10,
                "amount_cents" => amount_cents
              },
              "sort" => [amount_cents, id]
            }
          end
        end
      end
    end
  end
end
