# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require_relative "datastore_query_unit_support"
require "support/sort"

module ElasticGraph
  class GraphQL
    RSpec.describe DatastoreQuery, "sorting" do
      include_context "DatastoreQueryUnitSupport"
      include SortSupport

      it "uses only the tiebreaker sort clauses when given an empty `sort`" do
        query = new_query(sort: [], individual_docs_needed: true)
        expect(datastore_body_of(query)).to include_sort_with_tiebreaker
      end

      it "ignores duplicate sort fields, preferring whichever direction comes first" do
        query = new_query(sort: [{"foo" => {"order" => "asc"}}, {"foo" => {"order" => "desc"}}], individual_docs_needed: true)
        expect(datastore_body_of(query)).to include(sort: [{"foo" => {"order" => "asc", "missing" => "_first"}}, {"id" => {"order" => "asc", "missing" => "_first"}}])

        query = new_query(sort: [{"foo" => {"order" => "desc"}}, {"foo" => {"order" => "asc"}}], individual_docs_needed: true)
        expect(datastore_body_of(query)).to include(sort: [{"foo" => {"order" => "desc", "missing" => "_last"}}, {"id" => {"order" => "asc", "missing" => "_first"}}])
      end

      it "sets `sort:` when given a non-nil `sort`" do
        query = new_query(sort: [{created_at: {"order" => "asc"}}], individual_docs_needed: true)
        expect(datastore_body_of(query)).to include_sort_with_tiebreaker(created_at: {"order" => "asc"})
      end

      it "omits `sort` when `individual_docs_needed` is `false` since there will be no documents to sort" do
        query = new_query(sort: [{created_at: {"order" => "asc"}}], individual_docs_needed: false)

        expect(datastore_body_of(query)).to exclude("sort", :sort)
      end

      def include_sort_with_tiebreaker(*sort_clauses)
        include(sort: sort_list_with_missing_option_for(*sort_clauses))
      end
    end
  end
end
