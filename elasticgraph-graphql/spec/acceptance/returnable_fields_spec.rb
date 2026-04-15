# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require_relative "elasticgraph_graphql_acceptance_support"

module ElasticGraph
  RSpec.describe "ElasticGraph::GraphQL--returnable fields" do
    include_context "ElasticGraph GraphQL acceptance support"

    with_both_casing_forms do
      let(:aggregated_values) { case_correctly("aggregated_values") }
      let(:approximate_distinct_value_count) { case_correctly("approximate_distinct_value_count") }
      let(:grouped_by) { case_correctly("grouped_by") }
      let(:internal_details) { case_correctly("internal_details") }
      let(:internal_highlightable_details) { case_correctly("internal_highlightable_details") }
      let(:internal_highlightable_name) { case_correctly("internal_highlightable_name") }
      let(:internal_name) { case_correctly("internal_name") }
      let(:widget_aggregations) { case_correctly("widget_aggregations") }
      let(:widgets) { case_correctly("widgets") }

      it "supports filtering, sorting, grouping, and aggregating a hidden leaf field excluded from `_source`, plus highlighting when explicitly opted in" do
        index_records(
          build(:widget, id: "w1", internal_name: "alpha secret", internal_highlightable_name: "alpha public"),
          build(:widget, id: "w2", internal_name: "beta secret", internal_highlightable_name: "beta public"),
          build(:widget, id: "w3", internal_name: "gamma hidden", internal_highlightable_name: "gamma private")
        )

        response = call_graphql_query(<<~QUERY)
          query {
            widgets(
              filter: {
                internal_name: {
                  contains: {
                    any_substring_of: ["secret"]
                  }
                }
                internal_highlightable_name: {
                  contains: {
                    any_substring_of: ["public"]
                  }
                }
              }
              order_by: [#{internal_name}_ASC]
            ) {
              edges {
                node {
                  id
                }

                highlights {
                  internal_highlightable_name
                }
              }
            }

            widget_aggregations {
              nodes {
                grouped_by {
                  internal_name
                }

                count

                aggregated_values {
                  internal_name {
                    approximate_distinct_value_count
                  }
                }
              }
            }
          }
        QUERY

        expect(response.dig("data", widgets, "edges").map { |edge| edge.dig("node", "id") }).to eq(%w[w1 w2])
        expect(response.dig("data", widgets, "edges").to_h { |edge| [edge.dig("node", "id"), edge.dig("highlights", internal_highlightable_name)] }).to eq({
          "w1" => ["<em>alpha public</em>"],
          "w2" => ["<em>beta public</em>"]
        })

        aggregation_nodes = response
          .dig("data", widget_aggregations, "nodes")
          .sort_by { |node| node.dig(grouped_by, internal_name) }

        expect(aggregation_nodes).to eq([
          {
            grouped_by => {internal_name => "alpha secret"},
            "count" => 1,
            aggregated_values => {internal_name => {approximate_distinct_value_count => 1}}
          },
          {
            grouped_by => {internal_name => "beta secret"},
            "count" => 1,
            aggregated_values => {internal_name => {approximate_distinct_value_count => 1}}
          },
          {
            grouped_by => {internal_name => "gamma hidden"},
            "count" => 1,
            aggregated_values => {internal_name => {approximate_distinct_value_count => 1}}
          }
        ])

        expect {
          hidden_field_response = call_graphql_query(<<~QUERY, allow_errors: true)
            query {
              widgets {
                edges {
                  node {
                    id
                    internal_name
                  }
                }
              }
            }
          QUERY

          expect_error_related_to(hidden_field_response, "Widget", internal_name, "doesn't exist on type")
        }.to log(a_string_including("Widget", internal_name, "doesn't exist on type"))

        expect {
          hidden_field_response = call_graphql_query(<<~QUERY, allow_errors: true)
            query {
              widgets {
                edges {
                  node {
                    id
                    internal_highlightable_name
                  }
                }
              }
            }
          QUERY

          expect_error_related_to(hidden_field_response, "Widget", internal_highlightable_name, "doesn't exist on type")
        }.to log(a_string_including("Widget", internal_highlightable_name, "doesn't exist on type"))
      end

      it "supports filtering, grouping, and aggregating a hidden object field excluded from `_source`, plus highlighting when explicitly opted in" do
        index_records(
          build(:widget, id: "w1",
            internal_details: build(:widget_internal_details, name: "alpha vault"),
            internal_highlightable_details: build(:widget_internal_details, name: "alpha public")),
          build(:widget, id: "w2",
            internal_details: build(:widget_internal_details, name: "beta vault"),
            internal_highlightable_details: build(:widget_internal_details, name: "beta public")),
          build(:widget, id: "w3",
            internal_details: build(:widget_internal_details, name: "gamma archive"),
            internal_highlightable_details: build(:widget_internal_details, name: "gamma private"))
        )

        response = call_graphql_query(<<~QUERY)
          query {
            widgets(
              filter: {
                internal_details: {
                  name: {
                    contains: {
                      any_substring_of: ["vault"]
                    }
                  }
                }
                internal_highlightable_details: {
                  name: {
                    contains: {
                      any_substring_of: ["public"]
                    }
                  }
                }
              }
            ) {
              edges {
                node {
                  id
                }

                highlights {
                  internal_highlightable_details {
                    name
                  }
                }
              }
            }

            widget_aggregations {
              nodes {
                grouped_by {
                  internal_details {
                    name
                  }
                }

                count

                aggregated_values {
                  internal_details {
                    name {
                      approximate_distinct_value_count
                    }
                  }
                }
              }
            }
          }
        QUERY

        expect(response.dig("data", widgets, "edges").map { |edge| edge.dig("node", "id") }).to match_array(%w[w1 w2])
        expect(response.dig("data", widgets, "edges").to_h { |edge| [edge.dig("node", "id"), edge.dig("highlights", internal_highlightable_details, "name")] }).to eq({
          "w1" => ["<em>alpha public</em>"],
          "w2" => ["<em>beta public</em>"]
        })

        aggregation_nodes = response
          .dig("data", widget_aggregations, "nodes")
          .sort_by { |node| node.dig(grouped_by, internal_details, "name") }

        expect(aggregation_nodes).to eq([
          {
            grouped_by => {internal_details => {"name" => "alpha vault"}},
            "count" => 1,
            aggregated_values => {internal_details => {"name" => {approximate_distinct_value_count => 1}}}
          },
          {
            grouped_by => {internal_details => {"name" => "beta vault"}},
            "count" => 1,
            aggregated_values => {internal_details => {"name" => {approximate_distinct_value_count => 1}}}
          },
          {
            grouped_by => {internal_details => {"name" => "gamma archive"}},
            "count" => 1,
            aggregated_values => {internal_details => {"name" => {approximate_distinct_value_count => 1}}}
          }
        ])

        expect {
          hidden_field_response = call_graphql_query(<<~QUERY, allow_errors: true)
            query {
              widgets {
                edges {
                  node {
                    id
                    internal_details {
                      name
                    }
                  }
                }
              }
            }
          QUERY

          expect_error_related_to(hidden_field_response, "Widget", internal_details, "doesn't exist on type")
        }.to log(a_string_including("Widget", internal_details, "doesn't exist on type"))

        expect {
          hidden_field_response = call_graphql_query(<<~QUERY, allow_errors: true)
            query {
              widgets {
                edges {
                  node {
                    id
                    internal_highlightable_details {
                      name
                    }
                  }
                }
              }
            }
          QUERY

          expect_error_related_to(hidden_field_response, "Widget", internal_highlightable_details, "doesn't exist on type")
        }.to log(a_string_including("Widget", internal_highlightable_details, "doesn't exist on type"))
      end
    end
  end
end
