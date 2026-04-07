# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require_relative "elasticgraph_graphql_acceptance_support"

module ElasticGraph
  RSpec.describe "ElasticGraph::GraphQL--automatic field retrieval" do
    include_context "ElasticGraph GraphQL acceptance support"

    with_both_casing_forms do
      it "preserves scalar values, aliases, cursors, and page info through the real GraphQL pipeline" do
        index_records(
          build(:widget, id: "w1", name: nil, amount_cents: 0, workspace_id: "ws1"),
          build(:widget, id: "w2", name: "second", amount_cents: 2, workspace_id: "ws2")
        )
        query = <<~GRAPHQL
          query {
            widgets(first: 1, order_by: [id_ASC]) {
              edges { cursor node { id name amount_cents workspace: workspace_id } }
              page_info { has_next_page end_cursor }
            }
          }
        GRAPHQL
        automatic = build_graphql(experimental_field_retrieval: "automatic")
        source = call_graphql_query(query).to_h
        expect(call_graphql_query(query, gql: automatic).to_h).to eq(source)
        expect(logged_jsons_of_type("ElasticGraphQueryExecutorQueryDuration").last.fetch("field_retrieval_counts")).to include("doc_values" => 1)
        cursor = source.dig("data", "widgets", case_correctly("page_info"), case_correctly("end_cursor"))
        next_query = query.sub("first: 1", "first: 1, after: #{cursor.to_json}")
        expect(call_graphql_query(next_query, gql: automatic).to_h).to eq(call_graphql_query(next_query).to_h)
      end

      it "preserves lists and object structure by falling back to source" do
        index_records(build(:widget, tags: ["b", "a", "b"], name: "example"))
        query = "{ widgets { nodes { id name tags options { size } } } }"
        automatic = build_graphql(experimental_field_retrieval: "automatic")
        expect(call_graphql_query(query, gql: automatic).to_h).to eq(call_graphql_query(query).to_h)
        reasons = logged_jsons_of_type("ElasticGraphQueryExecutorQueryDuration").flat_map { |log| log.fetch("field_retrieval_counts").keys }
        expect(reasons).to include("source_ineligible_fields")
        expect(reasons).not_to include("doc_values")
      end

      it "preserves batched relationships whose join keys are returned from doc values", :expect_search_routing do
        index_records(
          build(:manufacturer, id: "m1", name: "first"),
          build(:manufacturer, id: "m2", name: "second"),
          build(:address, id: "a1", manufacturer_id: "m1"),
          build(:address, id: "a2", manufacturer_id: "m2")
        )
        query = <<~GRAPHQL
          { manufacturers(order_by: [id_ASC]) { nodes { id name address { manufacturer { id name } } } } }
        GRAPHQL
        automatic = build_graphql(experimental_field_retrieval: "automatic")
        expected = call_graphql_query(query).to_h
        expect(expected.dig("data", "manufacturers", "nodes").map { |node| node.dig("address", "manufacturer", "id") }).to eq %w[m1 m2]
        expect(call_graphql_query(query, gql: automatic).to_h).to eq expected
        expect(logged_jsons_of_type("ElasticGraphQueryExecutorQueryDuration").last.fetch("field_retrieval_counts").keys).to eq ["doc_values"]
      end

      it "preserves false through source-free boolean retrieval" do
        index_records(build(:physical_store, active: false))
        query = "{ physical_stores { nodes { id active } } }"
        automatic = build_graphql(experimental_field_retrieval: "automatic")
        expected = call_graphql_query(query).to_h
        expect(expected.dig("data", case_correctly("physical_stores"), "nodes").map { |node| node.fetch("active") }).to eq [false]
        expect(call_graphql_query(query, gql: automatic).to_h).to eq expected
        expect(logged_jsons_of_type("ElasticGraphQueryExecutorQueryDuration").last.fetch("field_retrieval_counts")).to include("doc_values" => 1)
      end

      it "retains abstract type discrimination and boolean values on source" do
        index_records(build(:online_store, active: false), build(:direct_wholesaler, active: true))
        query = "{ distribution_channels { nodes { id __typename active } } }"
        automatic = build_graphql(experimental_field_retrieval: "automatic")
        expected = call_graphql_query(query).to_h
        expect(expected.dig("data", case_correctly("distribution_channels"), "nodes").map { |node| node.fetch("active") }).to contain_exactly(false, true)
        expect(call_graphql_query(query, gql: automatic).to_h).to eq expected
        expect(logged_jsons_of_type("ElasticGraphQueryExecutorQueryDuration").last.fetch("field_retrieval_counts")).to include("source_ineligible_fields" => 1)
      end
    end
  end
end
