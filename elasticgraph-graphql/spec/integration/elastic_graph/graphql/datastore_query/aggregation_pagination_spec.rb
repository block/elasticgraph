# Copyright 2024 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require_relative "datastore_query_integration_support"
require_relative "pagination_shared_examples"
require "elastic_graph/graphql/aggregation/resolvers/relay_connection_builder"
require "support/aggregations_helpers"

module ElasticGraph
  class GraphQL
    RSpec.describe DatastoreQuery, "aggregation pagination" do
      include_context "DatastoreQueryIntegrationSupport"

      include_examples "DatastoreQuery pagination--integration" do
        include AggregationsHelpers

        let(:item1) { {"name" => "w1"} }
        let(:item2) { {"name" => "w2"} }
        let(:item3) { {"name" => "w3"} }
        let(:item4) { {"name" => "w4"} }
        let(:item5) { {"name" => "w5"} }
        let(:item_with_null) { {"name" => nil} }

        before do
          index_into(
            graphql,
            build(:widget, name: "w1", amount_cents: 10, created_at: "2022-01-01T00:00:00Z"),
            build(:widget, name: "w2", amount_cents: 20, created_at: "2022-02-01T00:00:00Z"),
            build(:widget, name: "w3", amount_cents: 30, created_at: "2022-03-01T00:00:00Z"),
            build(:widget, name: "w2", amount_cents: 40, created_at: "2022-02-01T00:00:00Z"),
            build(:widget, name: "w4", amount_cents: 50, created_at: "2022-04-01T00:00:00Z"),
            build(:widget, name: "w5", amount_cents: 60, created_at: "2022-05-01T00:00:00Z")
          )
        end

        def index_doc_with_null_value
          index_into(graphql, build(:widget, name: nil))
        end

        it "can paginate an aggregations result that has no groupings or computations" do
          paginated_search = ->(**options) { paginated_search(groupings: [], computations: [], **options) }

          items, page_info = paginated_search.call(first: 2)
          expect(items.map(&:count)).to eq [6]
          expect(page_info).to have_attributes(has_next_page: false, has_previous_page: false)

          items, page_info = paginated_search.call(first: 2, after: DecodedCursor::SINGLETON)
          expect(items).to be_empty
          expect(page_info).to have_attributes(has_next_page: false, has_previous_page: true)

          items, page_info = paginated_search.call(last: 2, before: DecodedCursor::SINGLETON)
          expect(items).to be_empty
          expect(page_info).to have_attributes(has_next_page: true, has_previous_page: false)

          items, page_info = paginated_search.call(after: DecodedCursor::SINGLETON, before: DecodedCursor::SINGLETON)
          expect(items).to be_empty
          expect(page_info).to have_attributes(has_next_page: false, has_previous_page: false)
        end

        it "can paginate an aggregations result that has no groupings but has computations" do
          paginated_search = ->(**options) { paginated_search(groupings: [], computations: [computation_of("amount_cents", :sum)], **options) }

          items, page_info = paginated_search.call(first: 2)
          expect(items.map { |i| fetch_aggregated_values(i, "amount_cents", "sum") }).to eq [210]
          expect(page_info).to have_attributes(has_next_page: false, has_previous_page: false)

          items, page_info = paginated_search.call(first: 2, after: DecodedCursor::SINGLETON)
          expect(items).to be_empty
          expect(page_info).to have_attributes(has_next_page: false, has_previous_page: true)

          items, page_info = paginated_search.call(last: 2, before: DecodedCursor::SINGLETON)
          expect(items).to be_empty
          expect(page_info).to have_attributes(has_next_page: true, has_previous_page: false)

          items, page_info = paginated_search.call(after: DecodedCursor::SINGLETON, before: DecodedCursor::SINGLETON)
          expect(items).to be_empty
          expect(page_info).to have_attributes(has_next_page: false, has_previous_page: false)
        end

        it "can paginate an aggregations result that has a date histogram grouping" do
          paginated_search = ->(**options) { paginated_search(groupings: [date_histogram_grouping_of("created_at", "month")], computations: [computation_of("amount_cents", :sum)], **options) }

          items, page_info = paginated_search.call(first: 2)
          expect(items.to_h { |i| [fetch_grouped_by(i, "created_at"), fetch_aggregated_values(i, "amount_cents", "sum")] }).to eq({
            "2022-01-01T00:00:00.000Z" => 10,
            "2022-02-01T00:00:00.000Z" => 60
          })
          expect(page_info).to have_attributes(has_next_page: true, has_previous_page: false)

          items, page_info = paginated_search.call(first: 2, after: items.last.cursor)
          expect(items.to_h { |i| [fetch_grouped_by(i, "created_at"), fetch_aggregated_values(i, "amount_cents", "sum")] }).to eq({
            "2022-03-01T00:00:00.000Z" => 30,
            "2022-04-01T00:00:00.000Z" => 50
          })
          expect(page_info).to have_attributes(has_next_page: true, has_previous_page: true)

          items, page_info = paginated_search.call(first: 2, after: items.last.cursor)
          expect(items.to_h { |i| [fetch_grouped_by(i, "created_at"), fetch_aggregated_values(i, "amount_cents", "sum")] }).to eq({
            "2022-05-01T00:00:00.000Z" => 60
          })
          expect(page_info).to have_attributes(has_next_page: false, has_previous_page: true)
        end

        def paginated_search(first: nil, after: nil, last: nil, before: nil, groupings: [field_term_grouping_of("name")], computations: [], filter_to: nil)
          aggregation_query = aggregation_query_of(
            groupings: groupings, computations: computations,
            first: first, after: after, last: last, before: before,
            max_page_size: graphql.config.max_page_size,
            default_page_size: graphql.config.default_page_size
          )

          response = search_datastore(
            document_pagination: {first: 0}, # make sure we don't ask for any documents, just aggregations.
            aggregations: [aggregation_query],
            total_document_count_needed: groupings.empty?,
            filters: [({"name" => {"equal_to_any_of" => ids_of(filter_to)}} if filter_to)].compact
          )

          connection = Aggregation::Resolvers::RelayConnectionBuilder.build_from_search_response(
            query: aggregation_query,
            search_response: response,
            schema_element_names: graphql.runtime_metadata.schema_element_names
          )

          [connection.nodes, connection.page_info]
        end

        def ids_of(*items)
          items.flatten.map do |item|
            if item.is_a?(Aggregation::Resolvers::Node)
              fetch_grouped_by(item, "name")
            else
              item.fetch("name")
            end
          end
        end

        def fetch_grouped_by(node, field)
          node.bucket.fetch("key").fetch(field)
        end

        def fetch_aggregated_values(node, *field_path, function_name)
          key = Aggregation::Key::AggregatedValue.new(
            aggregation_name: "aggregations",
            field_path: field_path,
            function_name: function_name
          )

          node.bucket.fetch(key.encode).fetch("value")
        end
      end
    end
  end
end
