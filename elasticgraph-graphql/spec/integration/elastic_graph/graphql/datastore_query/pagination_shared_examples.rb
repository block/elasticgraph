# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  class GraphQL
    RSpec.shared_examples_for "DatastoreQuery pagination--integration" do
      let(:graphql) { build_graphql(default_page_size: 3) }

      it "returns the first `default_page_size` items when no pagination args are provided" do
        items, page_info = paginated_search

        expect(ids_of(items)).to eq ids_of(item1, item2, item3)
        expect(page_info).to have_attributes(has_previous_page: false, has_next_page: true)
      end

      it "can paginate forward and backward when sorting ascending" do
        items, page_info = paginated_search(first: 2)
        expect(ids_of(items)).to eq ids_of(item1, item2)
        expect(page_info).to have_attributes(has_previous_page: false, has_next_page: true)

        items, page_info = paginated_search(first: 2, after: items.last.cursor)
        expect(ids_of(items)).to eq ids_of(item3, item4)
        expect(page_info).to have_attributes(has_previous_page: true, has_next_page: true)

        items, page_info = paginated_search(last: 2)
        expect(ids_of(items)).to eq ids_of(item4, item5)
        expect(page_info).to have_attributes(has_previous_page: true, has_next_page: false)

        items, page_info = paginated_search(last: 2, before: items.first.cursor)
        expect(ids_of(items)).to eq ids_of(item2, item3)
        expect(page_info).to have_attributes(has_previous_page: true, has_next_page: true)
      end

      it "sorts ascending and paginates correctly when a node has `null` for the field being sorted on" do
        index_doc_with_null_value

        # Forward paginate with ascending sort...
        items, page_info = paginated_search(first: 4)
        expect(ids_of(items)).to eq ids_of(item_with_null, item1, item2, item3)
        expect(page_info).to have_attributes(has_previous_page: false, has_next_page: true)

        items, page_info = paginated_search(first: 4, after: items.last.cursor)
        expect(ids_of(items)).to eq ids_of(item4, item5)
        expect(page_info).to have_attributes(has_previous_page: true, has_next_page: false)

        items, page_info = paginated_search(first: 4, after: items.last.cursor)
        expect(ids_of(items)).to be_empty
        expect(page_info).to have_attributes(has_previous_page: true, has_next_page: false)

        # Backward paginate with ascending sort...
        items, page_info = paginated_search(last: 4)
        expect(ids_of(items)).to eq ids_of(item2, item3, item4, item5)
        expect(page_info).to have_attributes(has_previous_page: true, has_next_page: false)

        items, page_info = paginated_search(last: 4, before: items.first.cursor)
        expect(ids_of(items)).to eq ids_of(item_with_null, item1)
        expect(page_info).to have_attributes(has_previous_page: false, has_next_page: true)

        items, page_info = paginated_search(last: 4, before: items.first.cursor)
        expect(ids_of(items)).to be_empty
        expect(page_info).to have_attributes(has_previous_page: false, has_next_page: true)

        # Forward paginate with ascending sort 1 node at a time (to ensure that the cursor references the node with a `null` value)...
        items, page_info = paginated_search(first: 1)
        expect(ids_of(items)).to eq ids_of(item_with_null)
        expect(page_info).to have_attributes(has_previous_page: false, has_next_page: true)

        [item1, item2, item3, item4].each do |item|
          items, page_info = paginated_search(first: 1, after: items.last.cursor)
          expect(ids_of(items)).to eq ids_of(item)
          expect(page_info).to have_attributes(has_previous_page: true, has_next_page: true)
        end

        items, page_info = paginated_search(first: 1, after: items.last.cursor)
        expect(ids_of(items)).to eq ids_of(item5)
        expect(page_info).to have_attributes(has_previous_page: true, has_next_page: false)

        items, page_info = paginated_search(first: 1, after: items.last.cursor)
        expect(ids_of(items)).to be_empty
        expect(page_info).to have_attributes(has_previous_page: true, has_next_page: false)

        # Backwards paginate with ascending sort 1 node at a time (to ensure that the cursor references the node with a `null` value)...
        items, page_info = paginated_search(last: 1)
        expect(ids_of(items)).to eq ids_of(item5)
        expect(page_info).to have_attributes(has_previous_page: true, has_next_page: false)

        [item4, item3, item2, item1].each do |item|
          items, page_info = paginated_search(last: 1, before: items.first.cursor)
          expect(ids_of(items)).to eq ids_of(item)
          expect(page_info).to have_attributes(has_previous_page: true, has_next_page: true)
        end

        items, page_info = paginated_search(last: 1, before: items.first.cursor)
        expect(ids_of(items)).to eq ids_of(item_with_null)
        expect(page_info).to have_attributes(has_previous_page: false, has_next_page: true)

        items, page_info = paginated_search(last: 1, before: items.first.cursor)
        expect(ids_of(items)).to be_empty
        expect(page_info).to have_attributes(has_previous_page: false, has_next_page: true)
      end

      it "can jump to the middle using just `before` or `after` without `first` and `last`" do
        items, page_info = paginated_search(before: cursor_of(item5))
        expect(ids_of(items)).to eq ids_of(item2, item3, item4)
        expect(page_info).to have_attributes(has_previous_page: true, has_next_page: true)

        items, page_info = paginated_search(after: cursor_of(item1))
        expect(ids_of(items)).to eq ids_of(item2, item3, item4)
        expect(page_info).to have_attributes(has_previous_page: true, has_next_page: true)
      end

      it "returns the last y of the first x when `first: x, last: y` is provided" do
        items, page_info = paginated_search(first: 4, last: 2)
        expect(ids_of(items)).to eq ids_of(item3, item4)
        expect(page_info).to have_attributes(has_previous_page: true, has_next_page: true)

        items, page_info = paginated_search(first: 2, last: 4)
        expect(ids_of(items)).to eq ids_of(item1, item2)
        expect(page_info).to have_attributes(has_previous_page: false, has_next_page: true)

        items, page_info = paginated_search(first: 3, after: cursor_of(item1), last: 2)
        expect(ids_of(items)).to eq ids_of(item3, item4)
        expect(page_info).to have_attributes(has_previous_page: true, has_next_page: true)

        items, page_info = paginated_search(first: 2, after: cursor_of(item1), last: 3)
        expect(ids_of(items)).to eq ids_of(item2, item3)
        expect(page_info).to have_attributes(has_previous_page: true, has_next_page: true)

        items, page_info = paginated_search(first: 3, last: 2, before: cursor_of(item4))
        expect(ids_of(items)).to eq ids_of(item2, item3)
        expect(page_info).to have_attributes(has_previous_page: true, has_next_page: true)

        items, page_info = paginated_search(first: 3, after: cursor_of(item1), last: 2, before: cursor_of(item4))
        expect(ids_of(items)).to eq ids_of(item2, item3)
        expect(page_info).to have_attributes(has_previous_page: true, has_next_page: true)
      end

      it "excludes documents with a cursor on or after `before` when either `first` or `after` are provided (which requires us to search the index from the start)" do
        items, page_info = paginated_search(first: 3, before: cursor_of(item5))
        expect(ids_of(items)).to eq ids_of(item1, item2, item3)
        expect(page_info).to have_attributes(has_previous_page: false, has_next_page: true)

        items, page_info = paginated_search(first: 3, before: cursor_of(item3))
        expect(ids_of(items)).to eq ids_of(item1, item2)
        expect(page_info).to have_attributes(has_previous_page: false, has_next_page: true)

        items, page_info = paginated_search(after: cursor_of(item1), before: cursor_of(item4))
        expect(ids_of(items)).to eq ids_of(item2, item3)
        expect(page_info).to have_attributes(has_previous_page: true, has_next_page: true)

        items, page_info = paginated_search(first: 3, last: 2, before: cursor_of(item3))
        expect(ids_of(items)).to eq ids_of(item1, item2)
        expect(page_info).to have_attributes(has_previous_page: false, has_next_page: true)

        items, page_info = paginated_search(first: 3, after: cursor_of(item1), before: cursor_of(item4))
        expect(ids_of(items)).to eq ids_of(item2, item3)
        expect(page_info).to have_attributes(has_previous_page: true, has_next_page: true)

        items, page_info = paginated_search(first: 3, after: cursor_of(item2), last: 3, before: cursor_of(item5))
        expect(ids_of(items)).to eq ids_of(item3, item4)
        expect(page_info).to have_attributes(has_previous_page: true, has_next_page: true)
      end

      it "excludes document with a cursor on or before `after` when `last` is provided without `first` (which requires us to search the index from the end)" do
        items, page_info = paginated_search(after: cursor_of(item2), last: 4)
        expect(ids_of(items)).to eq ids_of(item3, item4, item5)
        expect(page_info).to have_attributes(has_previous_page: true, has_next_page: false)

        items, page_info = paginated_search(after: cursor_of(item2), last: 3, before: cursor_of(item5))
        expect(ids_of(items)).to eq ids_of(item3, item4)
        expect(page_info).to have_attributes(has_previous_page: true, has_next_page: true)
      end

      it "correctly returns no results when `before` and `after` cancel out or one of `first` and `last` are 0" do
        items, page_info = paginated_search(after: cursor_of(item3), before: cursor_of(item4))
        expect(items).to eq []
        # Note: as explained in the comment on `Paginator#build_page_info`, it's not clear what the
        # "correct" value for `has_previous_page`/`has_next_page` page is when we are dealing with an empty
        # page, so here (and throughout this example)_ we just specify that it is a boolean of some sort.
        expect(page_info).to have_attributes(has_previous_page: a_boolean, has_next_page: a_boolean)

        items, page_info = paginated_search(first: 0, after: cursor_of(item1))
        expect(items).to eq []
        expect(page_info).to have_attributes(has_previous_page: a_boolean, has_next_page: a_boolean)

        items, page_info = paginated_search(first: 0, after: cursor_of(item2))
        expect(items).to eq []
        expect(page_info).to have_attributes(has_previous_page: a_boolean, has_next_page: a_boolean)

        items, page_info = paginated_search(last: 0, before: cursor_of(item4))
        expect(items).to eq []
        expect(page_info).to have_attributes(has_previous_page: a_boolean, has_next_page: a_boolean)

        items, page_info = paginated_search(last: 0, first: 0)
        expect(items).to eq []
        expect(page_info).to have_attributes(has_previous_page: a_boolean, has_next_page: a_boolean)
      end

      it "returns correct values for `has_next_page` and `has_previous_page` when the page only one element" do
        items, page_info = paginated_search(first: 1, after: cursor_of(item4))
        expect(ids_of(items)).to eq ids_of(item5)
        expect(page_info).to have_attributes(has_previous_page: true, has_next_page: false)

        items, page_info = paginated_search(last: 1, before: cursor_of(item2))
        expect(ids_of(items)).to eq ids_of(item1)
        expect(page_info).to have_attributes(has_previous_page: false, has_next_page: true)

        items, page_info = paginated_search(after: cursor_of(item2), before: cursor_of(item4))
        expect(ids_of(items)).to eq ids_of(item3)
        expect(page_info).to have_attributes(has_previous_page: true, has_next_page: true)

        items, page_info = paginated_search(first: 3, last: 1)
        expect(ids_of(items)).to eq ids_of(item3)
        expect(page_info).to have_attributes(has_previous_page: true, has_next_page: true)

        items, page_info = paginated_search(first: 5, last: 1)
        expect(ids_of(items)).to eq ids_of(item5)
        expect(page_info).to have_attributes(has_previous_page: true, has_next_page: false)
      end

      it "correctly handles the a page of one item when that item's cursor is used for `before` and/or `after`" do
        items, page_info = paginated_search(filter_to: item1)
        expect(ids_of(items)).to eq ids_of(item1)
        expect(page_info).to have_attributes(has_previous_page: false, has_next_page: false)

        items, page_info = paginated_search(filter_to: item1, before: cursor_of(item1))
        expect(ids_of(items)).to be_empty
        expect(page_info).to have_attributes(has_previous_page: false, has_next_page: true)

        items, page_info = paginated_search(filter_to: item1, after: cursor_of(item1))
        expect(ids_of(items)).to be_empty
        expect(page_info).to have_attributes(has_previous_page: true, has_next_page: false)

        items, page_info = paginated_search(filter_to: item1, before: cursor_of(item1), after: cursor_of(item1))
        expect(ids_of(items)).to be_empty
        expect(page_info).to have_attributes(has_previous_page: false, has_next_page: false)
      end

      it "raises `GraphQL::ExecutionError` when the cursor is lacking required information" do
        broken_cursor = DecodedCursor.new({"not" => "valid"})

        expect {
          paginated_search(first: 1, after: broken_cursor)
        }.to raise_error ::GraphQL::ExecutionError, a_string_including("`#{broken_cursor.encode}` is not a valid cursor")
      end

      it "raises errors when given a negative `first` or `last` option" do
        expect {
          paginated_search(last: -1)
        }.to raise_error(::GraphQL::ExecutionError, a_string_including("last", "negative", "-1"))

        expect {
          paginated_search(first: -7)
        }.to raise_error(::GraphQL::ExecutionError, a_string_including("first", "negative", "-7"))
      end

      def cursor_of(item)
        DecodedCursor.new(item)
      end
    end
  end
end
