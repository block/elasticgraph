# Copyright 2024 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require_relative "datastore_query_unit_support"
require "support/sort"
require "support/aggregations_helpers"

module ElasticGraph
  class GraphQL
    RSpec.describe DatastoreQuery, "#merge" do
      include SortSupport, AggregationsHelpers
      include_context "DatastoreQueryUnitSupport"

      before(:context) do
        # These are derived from app state and don't vary in two different queries for the same app,
        # so we don't have to deal with merging them.
        app_level_attributes = %i[
          logger filter_interpreter routing_picker index_expression_builder
          default_page_size max_page_size schema_element_names
        ]

        @attributes_needing_merge_test_coverage = (DatastoreQuery.members - app_level_attributes).to_set
      end

      before(:example) do |ex|
        Array(ex.metadata[:covers]).each do |attribute|
          @attributes_needing_merge_test_coverage.delete(attribute)
        end
      end

      after(:context) do
        expect(@attributes_needing_merge_test_coverage).to be_empty, "`#merge` tests are expected to cover all attributes, " \
          "but the following do not appear to have coverage: #{@attributes_needing_merge_test_coverage}"
      end

      it "throws exception if attempting to merge two queries with different `search_index_definitions` values", covers: :search_index_definitions do
        widgets_def = graphql.datastore_core.index_definitions_by_name.fetch("widgets")
        components_def = graphql.datastore_core.index_definitions_by_name.fetch("components")

        query1 = new_query(search_index_definitions: [widgets_def])
        query2 = new_query(search_index_definitions: [components_def])

        expect {
          merge(query1, query2)
        }.to raise_error(ElasticGraph::Errors::InvalidMergeError, a_string_including("search_index_definitions", "widgets", "components"))
      end

      it "can merge `equal_to_any_of` conditions from two separate queries that are on separate fields", covers: :filters do
        query1 = new_query(filters: [{"age" => {"equal_to_any_of" => [25, 30]}}])
        query2 = new_query(filters: [{"size" => {"equal_to_any_of" => [10]}}])

        merged = merge(query1, query2)

        expect(datastore_body_of(merged)).to filter_datastore_with(
          {terms: {"age" => [25, 30]}},
          {terms: {"size" => [10]}}
        )
      end

      it "can merge `equal_to_any_of` conditions from two separate queries that are on the same field", covers: :filters do
        query1 = new_query(filters: [{"age" => {"equal_to_any_of" => [25, 30]}}])
        query2 = new_query(filters: [{"age" => {"equal_to_any_of" => [35, 30]}}])

        merged = merge(query1, query2)

        expect(datastore_body_of(merged)).to filter_datastore_with(
          {terms: {"age" => [25, 30]}},
          {terms: {"age" => [35, 30]}}
        )
      end

      it "can merge using `merge_with(**query_options)` as well", covers: :filters do
        query1 = new_query(filters: [{"age" => {"equal_to_any_of" => [25, 30]}}])

        merged = nil

        expect {
          merged = query1.merge_with(filters: [{"age" => {"equal_to_any_of" => [35, 30]}, "size" => {"equal_to_any_of" => [10]}}])
        }.to maintain { query1 }.and maintain { query1.filters }

        expect(datastore_body_of(merged)).to filter_datastore_with(
          {terms: {"age" => [25, 30]}},
          {terms: {"age" => [35, 30]}},
          {terms: {"size" => [10]}}
        )
      end

      it "de-duplicates filters that are present in both queries", covers: :filters do
        query1 = new_query(filters: [{"age" => {"equal_to_any_of" => [25, 30]}}])

        merged = merge(query1, query1)

        expect(merged.filters).to contain_exactly({"age" => {"equal_to_any_of" => [25, 30]}})
      end

      it "uses only the tiebreaking sort clauses when merging two queries that have a `nil` sort", covers: :sort do
        query1 = new_query(sort: nil, individual_docs_needed: true)
        query2 = new_query(sort: nil, individual_docs_needed: true)

        expect(datastore_body_of(merge(query1, query2))).to include_sort_with_tiebreaker
      end

      it "does not use tiebreaking sort clauses when any of the two queries already specifies them", covers: :sort do
        # tiebreaker uses `asc` instead of `desc`
        query1 = new_query(sort: [{"id" => {"order" => "desc"}}], individual_docs_needed: true)
        query2 = new_query(sort: nil, individual_docs_needed: true)

        expect(datastore_body_of(merge(query1, query2))).to include(sort: [{"id" => {"order" => "desc", "missing" => "_last"}}])
      end

      it "uses the `sort` value from either query when only one of them has a value", covers: :sort do
        query1 = new_query(sort: [{created_at: {"order" => "asc"}}], individual_docs_needed: true)
        query2 = new_query(sort: nil, individual_docs_needed: true)

        merged = merge(query1, query2)
        merged_reverse = merge(query2, query1)

        expect(datastore_body_of(merged)).to include_sort_with_tiebreaker(created_at: {"order" => "asc"})
        expect(datastore_body_of(merged_reverse)).to eq(datastore_body_of(merged))
      end

      it "uses the `sort` value from the `query` argument when both queries have a `sort` value and logs a warning", covers: :sort do
        query1 = new_query(sort: [{created_at: {"order" => "asc"}}], individual_docs_needed: true)
        query2 = new_query(sort: [{created_at: {"order" => "desc"}}], individual_docs_needed: true)

        expect {
          merged = merge(query1, query2)
          expect(datastore_body_of(merged)).to include_sort_with_tiebreaker(created_at: {"order" => "desc"})
        }.to log a_string_including("Tried to merge two queries that both define `sort`")
      end

      it "uses one of the `sort` values when `sort` values are the same and does not log a warning", covers: :sort do
        query1 = new_query(sort: [{created_at: {"order" => "asc"}}], individual_docs_needed: true)
        query2 = new_query(sort: [{created_at: {"order" => "asc"}}], individual_docs_needed: true)

        expect {
          merged = merge(query1, query2)
          expect(datastore_body_of(merged)).to include_sort_with_tiebreaker(created_at: {"order" => "asc"})
        }.to avoid_logging_warnings
      end

      it "maintains a `document_pagination` value of `nil` when merging two queries that have a `nil` `document_pagination`", covers: :document_pagination do
        query1 = new_query(document_pagination: nil)
        query2 = new_query(document_pagination: nil)

        merged = merge(query1, query2)
        expect(merged.document_pagination).to eq({})
      end

      it "uses the `document_pagination` value from either query when only one of them has a value", covers: :document_pagination do
        query1 = new_query(document_pagination: {first: 2})
        query2 = new_query(document_pagination: nil)

        merged = merge(query1, query2)
        merged_reverse = merge(query2, query1)
        expect(merged.document_pagination).to eq({first: 2})
        expect(merged_reverse.document_pagination).to eq(merged.document_pagination)
      end

      it "uses the `document_pagination` value from the `query` argument when both queries have a `document_pagination` value and logs a warning", covers: :document_pagination do
        query1 = new_query(document_pagination: {first: 2})
        query2 = new_query(document_pagination: {first: 5})

        expect {
          merged = merge(query1, query2)
          expect(merged.document_pagination).to eq({first: 5})
        }.to log a_string_including("Tried to merge two queries that both define `document_pagination`")
      end

      it "uses one of the `document_pagination` values when `document_pagination` values are the same and does not log a warning", covers: :document_pagination do
        query1 = new_query(document_pagination: {first: 10})
        query2 = new_query(document_pagination: {first: 10})

        expect {
          merged = merge(query1, query2)
          expect(merged.document_pagination).to eq({first: 10})
        }.to avoid_logging_warnings
      end

      it "merges `aggregations` by merging the hashes", covers: :aggregations do
        agg1 = aggregation_query_of(name: "a1", groupings: [
          field_term_grouping_of("foo1", "bar1"),
          field_term_grouping_of("foo2", "bar2")
        ])

        agg2 = aggregation_query_of(name: "a2", groupings: [
          field_term_grouping_of("foo1", "bar1"),
          field_term_grouping_of("foo3", "bar3")
        ])

        agg3 = aggregation_query_of(name: "a3", groupings: [
          field_term_grouping_of("foo1", "bar1")
        ])

        query1 = new_query(aggregations: [agg1, agg3])
        query2 = new_query(aggregations: [agg2, agg3])

        merged1 = query1.merge(query2).aggregations
        merged2 = query2.merge(query1).aggregations

        expect(merged1).to eq(merged2)
        expect(merged1).to eq({
          "a1" => agg1,
          "a2" => agg2,
          "a3" => agg3
        })
      end

      it "correctly merges requested fields from multiple queries by concatenating and de-duplicating them", covers: :requested_fields do
        query1 = new_query(requested_fields: ["a", "b"])
        query2 = new_query(requested_fields: ["b", "c"])

        expect {
          expect(merge(query1, query2).requested_fields).to contain_exactly("a", "b", "c")
        }.to avoid_logging_warnings
      end

      it "sets `individual_docs_needed` to `true` if it is set on either query", covers: :individual_docs_needed do
        query1 = new_query(individual_docs_needed: true)
        query2 = new_query(individual_docs_needed: false)

        expect(query1.merge(query2).individual_docs_needed).to be true
        expect(query2.merge(query1).individual_docs_needed).to be true
      end

      it "sets `individual_docs_needed` to `false` if it is set to `false` on both queries", covers: :individual_docs_needed do
        query1 = new_query(individual_docs_needed: false)
        query2 = new_query(individual_docs_needed: false)

        expect(query1.merge(query2).individual_docs_needed).to be false
        expect(query2.merge(query1).individual_docs_needed).to be false
      end

      it "sets `total_document_count_needed` to `true` if it is set on either query", covers: :total_document_count_needed do
        query1 = new_query(total_document_count_needed: true)
        query2 = new_query(total_document_count_needed: false)

        expect(query1.merge(query2).total_document_count_needed).to be true
        expect(query2.merge(query1).total_document_count_needed).to be true
      end

      it "sets `total_document_count_needed` to `false` if it is set to `false` on both queries", covers: :total_document_count_needed do
        query1 = new_query(total_document_count_needed: false)
        query2 = new_query(total_document_count_needed: false)

        expect(query1.merge(query2).total_document_count_needed).to be false
        expect(query2.merge(query1).total_document_count_needed).to be false
      end

      it "forces `total_document_count_needed` to `true` if either query has an aggregation query that requires it", covers: :total_document_count_needed do
        query1 = new_query(total_document_count_needed: false, aggregations: [aggregation_query_of(needs_doc_count: true)])
        query2 = new_query(total_document_count_needed: false)

        expect(query1.merge(query2).total_document_count_needed).to be true
        expect(query2.merge(query1).total_document_count_needed).to be true
      end

      it "does not force `total_document_count_needed` to `true` if the aggregations query has groupings", covers: :total_document_count_needed do
        query1 = new_query(total_document_count_needed: false, aggregations: [aggregation_query_of(
          needs_doc_count: true,
          groupings: [field_term_grouping_of("age")]
        )])
        query2 = new_query(total_document_count_needed: false)

        expect(query1.merge(query2).total_document_count_needed).to be false
        expect(query2.merge(query1).total_document_count_needed).to be false
      end

      specify "#merge_with can merge in an empty filter", covers: :filters do
        query1 = new_query(filters: [{"age" => {"equal_to_any_of" => [25, 30]}}])

        expect(query1.merge_with).to eq query1
        expect(query1.merge_with(filters: [])).to eq query1
      end

      it "prefers a set `monotonic_clock_deadline` value to an unset one", covers: :monotonic_clock_deadline do
        query1 = new_query(monotonic_clock_deadline: 5000)
        query2 = new_query(monotonic_clock_deadline: nil)

        expect(query1.merge(query2).monotonic_clock_deadline).to eq 5000
        expect(query2.merge(query1).monotonic_clock_deadline).to eq 5000
      end

      it "prefers the shorter `monotonic_clock_deadline` value so that we can default to an application config setting, " \
         "and override it with a shorter deadline", covers: :monotonic_clock_deadline do
        query1 = new_query(monotonic_clock_deadline: 3000)
        query2 = new_query(monotonic_clock_deadline: 6000)

        expect(query1.merge(query2).monotonic_clock_deadline).to eq 3000
        expect(query2.merge(query1).monotonic_clock_deadline).to eq 3000
      end

      it "leaves `monotonic_clock_deadline` unset if unset on both source queries", covers: :monotonic_clock_deadline do
        query1 = new_query(monotonic_clock_deadline: nil)
        query2 = new_query(monotonic_clock_deadline: nil)

        expect(query1.merge(query2).monotonic_clock_deadline).to eq nil
        expect(query2.merge(query1).monotonic_clock_deadline).to eq nil
      end

      def filter_datastore_with(*filters)
        # `filter` uses the datastore's filtering context
        include(query: {bool: {filter: filters}})
      end

      def include_sort_with_tiebreaker(*sort_clauses)
        include(sort: sort_list_with_missing_option_for(*sort_clauses))
      end

      def merge(query1, query2)
        merged = nil

        # merging should not mutate either query, so we assert that here
        expect {
          merged = query1.merge(query2)
        }.to maintain { query1 }.and maintain { query2 }

        merged
      end
    end
  end
end
