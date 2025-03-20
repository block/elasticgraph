# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require_relative "datastore_query_integration_support"
require_relative "pagination_shared_examples"
require "elastic_graph/graphql/resolvers/relay_connection/search_response_adapter_builder"

module ElasticGraph
  class GraphQL
    RSpec.describe DatastoreQuery, "document pagination" do
      include_context "DatastoreQueryIntegrationSupport"

      let(:time1) { "2019-06-20T12:00:00Z" }
      let(:time2) { "2019-06-25T12:00:00Z" }

      let(:item1) { build(:widget, amount_cents: 100, id: "widget1", created_at: time1) }
      let(:item2) { build(:widget, amount_cents: 150, id: "widget2", created_at: time2) }
      let(:item3) { build(:widget, amount_cents: 200, id: "widget3", created_at: time1) }
      let(:item4) { build(:widget, amount_cents: 250, id: "widget4", created_at: time2) }
      let(:item5) { build(:widget, amount_cents: 300, id: "widget5", created_at: time1) }
      let(:item_with_null) { build(:widget, amount_cents: nil, id: "widget_with_null", created_at: time1) }

      let(:sort_list) { [{"amount_cents" => {"order" => "asc"}}] }
      let(:decoded_cursor_factory) { decoded_cursor_factory_for(sort_list) }

      before do
        index_into(graphql, item1, item2, item3, item4, item5)
      end

      include_examples "DatastoreQuery pagination--integration" do
        def index_doc_with_null_value
          index_into(graphql, item_with_null)
        end

        describe "pagination behaviors unique to document pagination" do
          # doesn't apply to aggregation pagination because it doesn't support a `pagination:` argument
          # (instead it has them "unwrapped").
          it "treats `document_pagination: nil`, `document_pagination: {}`, and no `document_pagination` arg the same" do
            items1, page_info1 = paginated_search
            expect(ids_of(items1)).to eq ids_of(item1, item2, item3)
            expect(page_info1).to have_attributes(has_previous_page: false, has_next_page: true)

            items2, page_info2 = paginated_search(document_pagination: nil)
            expect(items2).to eq items1
            expect(page_info2).to eq page_info1

            items3, page_info3 = paginated_search(document_pagination: {})
            expect(items3).to eq items1
            expect(page_info3).to eq page_info1
          end

          # We don't yet support specifying sorting on aggregation pagination, so this doesn't apply to that case.
          it "can paginate forward and backward when sorting descending" do
            paginated_search = ->(**options) { paginated_search(sort: [{"amount_cents" => {"order" => "desc"}}], **options) }

            items, page_info = paginated_search.call(first: 2)
            expect(ids_of(items)).to eq ids_of(item5, item4)
            expect(page_info).to have_attributes(has_previous_page: false, has_next_page: true)

            items, page_info = paginated_search.call(first: 2, after: items.last.cursor)
            expect(ids_of(items)).to eq ids_of(item3, item2)
            expect(page_info).to have_attributes(has_previous_page: true, has_next_page: true)

            items, page_info = paginated_search.call(last: 2)
            expect(ids_of(items)).to eq ids_of(item2, item1)
            expect(page_info).to have_attributes(has_previous_page: true, has_next_page: false)

            items, page_info = paginated_search.call(last: 2, before: items.first.cursor)
            expect(ids_of(items)).to eq ids_of(item4, item3)
            expect(page_info).to have_attributes(has_previous_page: true, has_next_page: true)
          end

          # We don't yet support specifying sorting on aggregation pagination, so this doesn't apply to that case.
          it "sorts descending and paginates correctly when a node has `null` for the field being sorted on" do
            index_doc_with_null_value

            paginated_search = ->(**options) { paginated_search(sort: [{"amount_cents" => {"order" => "desc"}}], **options) }

            # Forward paginate with descending sort...
            items, page_info = paginated_search.call(first: 4)
            expect(ids_of(items)).to eq ids_of(item5, item4, item3, item2)
            expect(page_info).to have_attributes(has_previous_page: false, has_next_page: true)

            items, page_info = paginated_search.call(first: 4, after: items.last.cursor)
            expect(ids_of(items)).to eq ids_of(item1, item_with_null)
            expect(page_info).to have_attributes(has_previous_page: true, has_next_page: false)

            items, page_info = paginated_search.call(first: 4, after: items.last.cursor)
            expect(ids_of(items)).to be_empty
            expect(page_info).to have_attributes(has_previous_page: true, has_next_page: false)

            # Backward paginate with descending sort...
            items, page_info = paginated_search.call(last: 4)
            expect(ids_of(items)).to eq ids_of(item3, item2, item1, item_with_null)
            expect(page_info).to have_attributes(has_previous_page: true, has_next_page: false)

            items, page_info = paginated_search.call(last: 4, before: items.first.cursor)
            expect(ids_of(items)).to eq ids_of(item5, item4)
            expect(page_info).to have_attributes(has_previous_page: false, has_next_page: true)

            items, page_info = paginated_search.call(last: 4, before: items.first.cursor)
            expect(ids_of(items)).to be_empty
            expect(page_info).to have_attributes(has_previous_page: false, has_next_page: true)

            # Forward paginate with descending sort 1 node at a time (to ensure that the cursor references the node with a `null` value)...
            items, page_info = paginated_search.call(first: 1)
            expect(ids_of(items)).to eq ids_of(item5)
            expect(page_info).to have_attributes(has_previous_page: false, has_next_page: true)

            [item4, item3, item2, item1].each do |item|
              items, page_info = paginated_search.call(first: 1, after: items.last.cursor)
              expect(ids_of(items)).to eq ids_of(item)
              expect(page_info).to have_attributes(has_previous_page: true, has_next_page: true)
            end

            items, page_info = paginated_search.call(first: 1, after: items.last.cursor)
            expect(ids_of(items)).to eq ids_of(item_with_null)
            expect(page_info).to have_attributes(has_previous_page: true, has_next_page: false)

            items, page_info = paginated_search.call(first: 1, after: items.last.cursor)
            expect(ids_of(items)).to be_empty
            expect(page_info).to have_attributes(has_previous_page: true, has_next_page: false)

            # Backward paginate with descending sort 1 node at a time (to ensure that the cursor references the node with a `null` value)...
            items, page_info = paginated_search.call(last: 1)
            expect(ids_of(items)).to eq ids_of(item_with_null)
            expect(page_info).to have_attributes(has_previous_page: true, has_next_page: false)

            [item1, item2, item3, item4].each do |item|
              items, page_info = paginated_search.call(last: 1, before: items.first.cursor)
              expect(ids_of(items)).to eq ids_of(item)
              expect(page_info).to have_attributes(has_previous_page: true, has_next_page: true)
            end

            items, page_info = paginated_search.call(last: 1, before: items.first.cursor)
            expect(ids_of(items)).to eq ids_of(item5)
            expect(page_info).to have_attributes(has_previous_page: false, has_next_page: true)

            items, page_info = paginated_search.call(last: 1, before: items.first.cursor)
            expect(ids_of(items)).to be_empty
            expect(page_info).to have_attributes(has_previous_page: false, has_next_page: true)
          end

          # We don't yet support specifying sorting on aggregation pagination, so this doesn't apply to that case.
          it "properly supports `before` and `after` when mixing ascending and descending sort clauses" do
            sort = [{"created_at" => {"order" => "asc"}}, {"amount_cents" => {"order" => "desc"}}]
            # sort order: item5, item3, item1, item4, item2
            reverse_sort = [{"created_at" => {"order" => "desc"}}, {"amount_cents" => {"order" => "asc"}}]
            decoded_cursor_factory = decoded_cursor_factory_for(sort)

            items, _page_info = paginated_search(sort: sort, after: cursor_of(item5, decoded_cursor_factory: decoded_cursor_factory), before: cursor_of(item2, decoded_cursor_factory: decoded_cursor_factory))
            expect(ids_of(items)).to eq ids_of(item3, item1, item4)

            items, _page_info = paginated_search(sort: reverse_sort, after: cursor_of(item2, decoded_cursor_factory: decoded_cursor_factory), before: cursor_of(item5, decoded_cursor_factory: decoded_cursor_factory))
            expect(ids_of(items)).to eq ids_of(item4, item1, item3)
          end

          # Aggregation pagination doesn't need to worry about this because grouping guarantees uniqueness of the keys that are encoded as cursors.
          it "ensures each edge has a unique cursor value, even when they have the same values for the requested sort fields, to avoid ambiguity" do
            index_into(graphql, item1b = item1.merge(id: item1.fetch(:id) + "b"))

            documents, _page_info = paginated_search(first: 2).to_a

            expect(ids_of(documents)).to eq ids_of(item1, item1b)
            expect(documents.map(&:cursor).uniq.count).to eq 2
          end
        end
      end

      def paginated_search(first: nil, after: nil, last: nil, before: nil, document_pagination: nil, sort: sort_list, filter_to: nil)
        document_pagination ||= {first: first, after: after, last: last, before: before}.compact
        query = nil
        response = search_datastore(
          sort: sort,
          document_pagination: document_pagination,
          filter: ({"id" => {"equal_to_any_of" => ids_of(filter_to)}} if filter_to)
        ) { |q| query = q }

        adapter = Resolvers::RelayConnection::SearchResponseAdapterBuilder.build_from(
          schema_element_names: SchemaArtifacts::RuntimeMetadata::SchemaElementNames.new(form: :snake_case, overrides: {}),
          search_response: response,
          query: query
        )

        [adapter.nodes, adapter.page_info]
      end

      def cursor_of(widget, decoded_cursor_factory: self.decoded_cursor_factory)
        values = decoded_cursor_factory.sort_fields.to_h do |field|
          value = widget.fetch(field.to_sym)
          # The datastore use integers (milliseconds since epoch) as sort values for timestamp fields.
          value = ::Time.parse(value).to_i * 1000 if field.end_with?("_at")
          [field, value]
        end

        DecodedCursor.new(values)
      end
    end
  end
end
