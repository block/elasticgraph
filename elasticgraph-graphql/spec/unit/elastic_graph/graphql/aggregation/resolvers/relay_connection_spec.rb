# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/constants"
require "elastic_graph/graphql/aggregation/resolvers/relay_connection_builder"
require "elastic_graph/support/hash_util"

module ElasticGraph
  class GraphQL
    module Aggregation
      module Resolvers
        RSpec.describe "RelayConnection for aggregations" do
          let(:indexed_widget_count) { 10000 }

          attr_accessor :schema_artifacts

          before(:context) do
            self.schema_artifacts = generate_schema_artifacts do |schema|
              schema.object_type "Widget" do |t|
                t.field "id", "ID!"
                t.field "workspace_id", "ID"
                t.field "name", "String"
                t.index "widgets"
              end
            end
          end

          context "when grouping by a field" do
            it "contains the requested number of groupings when the caller passed `first: N`" do
              results = execute_widgets_aggregation_query(<<~QUERY)
                widget_aggregations(first: 2) {
                  edges {
                    node {
                      grouped_by { workspace_id }
                      count
                    }
                  }
                }
              QUERY

              expect(results.dig("edges").size).to eq 2

              results = execute_widgets_aggregation_query(<<~QUERY)
                widget_aggregations(first: 3) {
                  edges {
                    node {
                      grouped_by { workspace_id }
                      count
                    }
                  }
                }
              QUERY

              expect(results.dig("edges").size).to eq 3
            end

            it "contains the default page size number of groupings when the caller does not pass `first: N`" do
              results = execute_widgets_aggregation_query(<<~QUERY, default_page_size: 5)
                widget_aggregations {
                  edges {
                    node {
                      grouped_by { workspace_id }
                      count
                    }
                  }
                }
              QUERY

              expect(results.dig("edges").size).to eq 5
            end

            it "returns the available number of buckets when it is less than the `first` arg" do
              results = execute_widgets_aggregation_query(<<~QUERY, available_buckets: 3)
                widget_aggregations(first: 5) {
                  edges {
                    node {
                      grouped_by { workspace_id }
                      count
                    }
                  }
                }
              QUERY

              expect(results.dig("edges").size).to eq 3
            end

            it "returns the available number of buckets when it is less than the default page size and no `first` arg was passed" do
              results = execute_widgets_aggregation_query(<<~QUERY, available_buckets: 3, default_page_size: 5)
                widget_aggregations {
                  edges {
                    node {
                      grouped_by { workspace_id }
                      count
                    }
                  }
                }
              QUERY

              expect(results.dig("edges").size).to eq 3
            end

            it "exposes a unique cursor for each `node`" do
              results = execute_widgets_aggregation_query(<<~QUERY)
                widget_aggregations(first: 3) {
                  edges {
                    cursor
                    node {
                      grouped_by { workspace_id }
                    }
                  }
                }
              QUERY

              expect(results.dig("edges")).to match [
                {"cursor" => /\w+/, "node" => {"grouped_by" => {"workspace_id" => "1"}}},
                {"cursor" => /\w+/, "node" => {"grouped_by" => {"workspace_id" => "2"}}},
                {"cursor" => /\w+/, "node" => {"grouped_by" => {"workspace_id" => "3"}}}
              ]

              cursors = cursors_from(results)
              expect(cursors.uniq).to match_array(cursors)
            end

            it "exposes the cursor of the first and last nodes as the `start_cursor` and `end_cursor`, respectively" do
              results = execute_widgets_aggregation_query(<<~QUERY)
                widget_aggregations(first: 3) {
                  page_info {
                    start_cursor
                    end_cursor
                  }

                  edges {
                    cursor
                    node {
                      grouped_by { workspace_id }
                    }
                  }
                }
              QUERY

              cursors = cursors_from(results)

              expect(results.dig("page_info")).to eq({
                "start_cursor" => cursors.first,
                "end_cursor" => cursors.last
              })
            end

            it "returns `null` for page_info cursors if there are no aggregation buckets" do
              results = execute_widgets_aggregation_query(<<~QUERY)
                widget_aggregations(first: 0) {
                  page_info {
                    start_cursor
                    end_cursor
                  }

                  edges {
                    cursor
                    node {
                      grouped_by { workspace_id }
                    }
                  }
                }
              QUERY

              expect(results.dig("edges")).to be_empty

              expect(results.dig("page_info")).to eq({
                "start_cursor" => nil,
                "end_cursor" => nil
              })
            end
          end

          context "when not grouping by anything" do
            it "returns a single bucket when no `first:` arg is passed" do
              results = execute_widgets_aggregation_query(<<~QUERY)
                widget_aggregations {
                  edges {
                    node {
                      count
                    }
                  }
                }
              QUERY

              expect(results.dig("edges").size).to eq 1
            end

            it "returns an empty collection of buckets when `first: 0` is passed" do
              results = execute_widgets_aggregation_query(<<~QUERY)
                widget_aggregations(first: 0) {
                  page_info {
                    start_cursor
                    end_cursor
                  }

                  edges {
                    node {
                      count
                    }
                  }
                }
              QUERY

              expect(results.dig("edges").size).to eq 0

              expect(results.dig("page_info")).to eq({
                "start_cursor" => nil,
                "end_cursor" => nil
              })
            end

            it "still exposes a cursor even though there can be at most one node, to satisfy the Relay spec" do
              results = execute_widgets_aggregation_query(<<~QUERY)
                widget_aggregations {
                  page_info {
                    start_cursor
                    end_cursor
                  }

                  edges {
                    cursor
                    node {
                      count
                    }
                  }
                }
              QUERY

              expect(results).to eq({
                "page_info" => {
                  "start_cursor" => SINGLETON_CURSOR,
                  "end_cursor" => SINGLETON_CURSOR
                },
                "edges" => [{
                  "cursor" => SINGLETON_CURSOR,
                  "node" => {
                    "count" => indexed_widget_count
                  }
                }]
              })
            end
          end

          it "supports multiple aliased aggregation fields with different groupings" do
            results = execute_widgets_aggregation_query(<<~QUERY, path: ["data"])
              by_workspace_id: widget_aggregations(first: 2) {
                edges {
                  node {
                    grouped_by { workspace_id }
                    count
                  }
                }
              }

              by_name: widget_aggregations(first: 3) {
                edges {
                  node {
                    grouped_by { name }
                    count
                  }
                }
              }
            QUERY

            expect(results.dig("by_workspace_id", "edges").size).to eq 2
            expect(results.dig("by_name", "edges").size).to eq 3
          end

          it "supports `nodes` being used instead of `edges`" do
            results = execute_widgets_aggregation_query(<<~QUERY)
              widget_aggregations(first: 3) {
                nodes {
                  grouped_by { workspace_id }
                }
              }
            QUERY

            expect(results.dig("nodes")).to match [
              {"grouped_by" => {"workspace_id" => "1"}},
              {"grouped_by" => {"workspace_id" => "2"}},
              {"grouped_by" => {"workspace_id" => "3"}}
            ]
          end

          def execute_widgets_aggregation_query(inner_query, available_buckets: nil, path: ["data", "widget_aggregations"], **config_overrides)
            allow(datastore_client).to receive(:msearch) do |request|
              build_datastore_response(request, available_buckets: available_buckets)
            end

            graphql = build_graphql(schema_artifacts: schema_artifacts, **config_overrides)

            query = "query { #{inner_query} }"
            response = graphql.graphql_query_executor.execute(query)
            expect(response["errors"]).to eq([]).or eq(nil)
            response.dig(*path)
          end

          # Builds a dynamic response for our fake datastore client, based on the request itself,
          # and the `available_buckets` (which limits how many groupings are "available" in the datastore)
          def build_datastore_response(request, available_buckets:)
            # Our query logic generates a payload with a mixture of string and symbol keys
            # (it doesn't matter to the datastore client since it serializes in JSON the same).
            # Here we do not want to be mix and match (or be coupled to the current key form
            # being used) so we normalize to string keys here.
            normalized_request = Support::HashUtil.stringify_keys(request)

            responses = normalized_request["body"].each_slice(2).map do |(search_header, search_body)|
              expect(search_header).to include("index" => "widgets")

              aggregations = search_body.fetch("aggs", {}).select { |k, v| v.key?("composite") }.to_h do |agg_name, agg_subhash|
                composite_agg_request = agg_subhash.fetch("composite")
                # We'll return the smaller of the requested count and the available count (defaults to unbounded)
                count_to_return = [composite_agg_request.fetch("size"), available_buckets].compact.min
                bucket_keys = composite_agg_request.fetch("sources").flat_map(&:keys)
                buckets = Array.new(count_to_return) { |i| build_bucket(i, bucket_keys) }

                [agg_name, {"after_key" => {}, "buckets" => buckets}]
              end

              datastore_response_payload_with_aggs(aggregations)
            end

            {"responses" => responses}
          end

          def datastore_response_payload_with_aggs(aggregations)
            {
              "took" => 25,
              "timed_out" => false,
              "_shards" => {"total" => 30, "successful" => 30, "skipped" => 0, "failed" => 0},
              "hits" => {"total" => {"value" => indexed_widget_count, "relation" => "eq"}, "max_score" => nil, "hits" => []},
              "aggregations" => aggregations,
              "status" => 200
            }.compact
          end

          def build_bucket(index, bucket_keys)
            {
              "key" => bucket_keys.each_with_object({}) { |key, hash| hash[key] = (index + 1).to_s },
              "doc_count" => (index + 1) * 2
            }
          end

          def cursors_from(results)
            results.fetch("edges").map { |e| e.fetch("cursor") }
          end
        end
      end
    end
  end
end
