# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require_relative "datastore_query_unit_support"

module ElasticGraph
  class GraphQL
    RSpec.describe DatastoreQuery, "pagination" do
      include_context "DatastoreQueryUnitSupport"
      let(:default_page_size) { 73 }
      let(:max_page_size) { 200 }
      let(:graphql) { build_graphql(default_page_size: default_page_size, max_page_size: max_page_size) }

      it "excludes `search_after` when document_pagination is empty" do
        query = new_query(document_pagination: {})
        expect(datastore_body_of(query).keys).to_not include(:search_after)
      end

      it "uses the configured default page size when not overridden by a document_pagination option" do
        query = new_query(individual_docs_needed: true)
        # we allow for `default_page_size + 1` so if we need to fetch an additional document
        # to see if there's another page, we can.
        expect(datastore_body_of(query)).to include(size: a_value_within(1).of(default_page_size))
      end

      it "limits the page size to the configured max page size" do
        query = new_query(individual_docs_needed: true, document_pagination: {first: max_page_size + 10})
        # we allow for `default_page_size + 1` so if we need to fetch an additional document
        # to see if there's another page, we can.
        expect(datastore_body_of(query)).to include(size: a_value_within(1).of(max_page_size))

        query = new_query(individual_docs_needed: true, document_pagination: {last: max_page_size + 10})
        # we allow for `default_page_size + 1` so if we need to fetch an additional document
        # to see if there's another page, we can.
        expect(datastore_body_of(query)).to include(size: a_value_within(1).of(max_page_size))
      end

      it "queries the datastore with a page size of 0 if `individual_docs_needed` is false" do
        query = new_query(requested_fields: [])
        expect(query.individual_docs_needed).to be false

        expect(datastore_body_of(query)).to include(size: 0)
      end

      it "applies the `size_multiplier` to the size we request from the datastore" do
        query = new_query(individual_docs_needed: true, document_pagination: {first: 7})
        multiplied_query = query.merge_with(size_multiplier: 3)

        # 24 because we add 1 to the "base" size and (7 + 1) * 3 = 24
        expect(datastore_body_of(multiplied_query)).to include(size: 24)
      end
    end
  end
end
