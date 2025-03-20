# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require_relative "elasticgraph_graphql_acceptance_support"

module ElasticGraph
  RSpec.describe "ElasticGraph::GraphQL--datastore tests" do
    include_context "ElasticGraph GraphQL acceptance support"

    with_both_casing_forms do
      it "avoids querying the datastore when it does not need to" do
        datastore_requests("main").clear

        # If we are just inspecting the schema, we shouldn't need to query the datastore...
        expect {
          results = call_graphql_query(<<~EOS).dig("data", "widgets")
            query {
              widgets {
                __typename
              }
            }
          EOS

          expect(results).to eq({"__typename" => apply_derived_type_customizations("WidgetConnection")})
        }.to make_no_datastore_calls("main")

        # ... or if we are asking for 0 results, we shouldn't have to...
        expect {
          results = call_graphql_query(<<~EOS).dig("data", "widgets")
            query {
              widgets(first: 0) {
                edges {
                  node {
                    id
                  }
                }
              }
            }
          EOS

          expect(results).to eq({"edges" => []})
        }.to make_no_datastore_calls("main")

        # ...but if we are just asking for page info, we still need to; there may still be a next page.
        expect {
          results = call_graphql_query(<<~EOS).dig("data", "widgets")
            query {
              widgets {
                page_info {
                  has_next_page
                }
              }
            }
          EOS

          expect(results).to eq({case_correctly("page_info") => {case_correctly("has_next_page") => false}})
        }.to make_datastore_calls("main", "GET /_msearch")
      end

      it "batches datastore queries when requesting indexed types in parallel" do
        expect {
          results = query_all_indexed_type_counts

          expect(results).to eq(
            "addresses" => {case_correctly("total_edge_count") => 0},
            "components" => {case_correctly("total_edge_count") => 0},
            case_correctly("electrical_parts") => {case_correctly("total_edge_count") => 0},
            "manufacturers" => {case_correctly("total_edge_count") => 0},
            case_correctly("mechanical_parts") => {case_correctly("total_edge_count") => 0},
            "parts" => {case_correctly("total_edge_count") => 0},
            "widgets" => {case_correctly("total_edge_count") => 0},
            case_correctly("widget_currencies") => {case_correctly("total_edge_count") => 0}
          )
        }.to query_datastore("main", 1).time
      end

      it "handles queries against non-existing fields in the datastore gracefully--such as when a new field is added to a rollover index template after the template has been used" do
        index_records(
          address1 = build(:address, created_at: "2019-09-10T12:00:00.000Z", full_address: "123"),
          address2 = build(:address, created_at: "2019-09-11T12:00:00.000Z", full_address: "456"),
          address3 = build(:address, created_at: "2019-09-12T12:00:00.000Z", full_address: "789")
        )

        schema_def_string = raw_schema_def_string.sub('schema.object_type "Address" do |t|', <<~EOS)
          schema.object_type "AddressLines" do |t|
            t.field "line1", "String"
            t.field "line2", "String"
          end

          schema.object_type "Address" do |t|
            t.field "lines", "AddressLines"
            t.field "postal_code", "String"
        EOS

        graphql_with_new_schema = build_graphql(schema_definition: ->(schema) do
          # standard:disable Security/Eval -- it's ok here in a test.
          schema.as_active_instance { eval(case_schema_def_correctly(schema_def_string)) }
          # standard:enable Security/Eval
        end)

        addresses = list_addresses(gql: graphql_with_new_schema, fields: <<~EOS, order_by: [:timestamps_created_at_ASC])
          full_address
          timestamps {
            created_at
          }
          postal_code
          lines {
            line1
            line2
          }
        EOS

        expect(addresses).to match([
          string_hash_of(address1, :timestamps, :full_address, "postal_code" => nil, "lines" => nil),
          string_hash_of(address2, :timestamps, :full_address, "postal_code" => nil, "lines" => nil),
          string_hash_of(address3, :timestamps, :full_address, "postal_code" => nil, "lines" => nil)
        ])
      end

      describe "timeout behavior" do
        it "raises `Errors::RequestExceededDeadlineError` if the specified timeout is exceeded by a datastore query" do
          expect {
            call_graphql_query(<<~QUERY, timeout_in_ms: 0)
              query { widgets { edges { node { id } } } }
            QUERY
          }.to raise_error(Errors::RequestExceededDeadlineError)
            .and log(a_string_including("failed with an exception", "Errors::RequestExceededDeadlineError"))
        end

        it "applies shorter timeouts to each subsequent datastore query as the monotonic clock passes so that the passed timeout applies to the entire GraphQL query", :expect_search_routing do
          component = build(:component)
          widget = build(:widget, components: [component])
          index_records(widget, component)

          # use a long (10 minute) timeout so that we definitely won't hit it, even if a debugger is used.
          long_timeout_seconds = 600

          call_graphql_query(<<~QUERY, timeout_in_ms: long_timeout_seconds * 1000)
            query {
              widgets { nodes {
                components { nodes { id name } }
              } }
            }
          QUERY

          timeouts = datastore_msearch_requests("main").map(&:timeout)

          expect(timeouts.size).to eq 2
          expect(timeouts.first).to be < long_timeout_seconds
          expect(timeouts.last).to be < timeouts.first
        end
      end

      def list_addresses(fields:, gql: graphql, **query_args)
        call_graphql_query(<<~QUERY, gql: gql).dig("data", "addresses", "edges").map { |we| we.fetch("node") }
          query {
            addresses#{graphql_args(query_args)} {
              edges {
                node {
                  #{fields}
                }
              }
            }
          }
        QUERY
      end

      def query_all_indexed_type_counts
        call_graphql_query(<<~QUERY).fetch("data")
          query {
            addresses { total_edge_count }
            components { total_edge_count }
            electrical_parts { total_edge_count }
            manufacturers { total_edge_count }
            mechanical_parts { total_edge_count }
            parts { total_edge_count }
            widgets { total_edge_count }
            widget_currencies { total_edge_count }
          }
        QUERY
      end
    end
  end
end
