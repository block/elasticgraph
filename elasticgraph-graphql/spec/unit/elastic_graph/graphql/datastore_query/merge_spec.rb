# Copyright 2024 - 2025 Block, Inc.
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
    RSpec.describe DatastoreQuery, "#merge", :capture_logs do
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

      it "does not allow `search_index_definitions` to be overridden", covers: :search_index_definitions do
        widgets_def = graphql.datastore_core.index_definitions_by_name.fetch("widgets")
        components_def = graphql.datastore_core.index_definitions_by_name.fetch("components")

        query = new_query(search_index_definitions: [widgets_def])

        expect {
          query.merge_with(search_index_definitions: [components_def])
        }.to raise_error ArgumentError, a_string_including("search_index_definitions")
      end

      %i[client_filters internal_filters].each do |filter_attr|
        describe ":#{filter_attr}", covers: filter_attr do
          it "can merge `equal_to_any_of` conditions from two separate queries that are on separate fields" do
            merged = merge(
              {filter_attr => [{"age" => {"equal_to_any_of" => [25, 30]}}]},
              {filter_attr => [{"size" => {"equal_to_any_of" => [10]}}]}
            )

            expect(datastore_body_of(merged)).to filter_datastore_with(
              {terms: {"age" => [25, 30]}},
              {terms: {"size" => [10]}}
            )
          end

          it "can merge `equal_to_any_of` conditions from two separate queries that are on the same field" do
            merged = merge(
              {filter_attr => [{"age" => {"equal_to_any_of" => [25, 30]}}]},
              {filter_attr => [{"age" => {"equal_to_any_of" => [35, 30]}}]}
            )

            expect(datastore_body_of(merged)).to filter_datastore_with(
              {terms: {"age" => [25, 30]}},
              {terms: {"age" => [35, 30]}}
            )
          end

          it "de-duplicates filters that are present in both queries" do
            merged = merge(
              {filter_attr => [{"age" => {"equal_to_any_of" => [25, 30]}}]},
              {filter_attr => [{"age" => {"equal_to_any_of" => [25, 30]}}]}
            )

            expect(merged.public_send(filter_attr)).to contain_exactly({"age" => {"equal_to_any_of" => [25, 30]}})
          end

          specify "#merge_with can merge in an empty filter" do
            query = new_query(filter_attr => [{"age" => {"equal_to_any_of" => [25, 30]}}])
            expect(query.merge_with).to eq query
            expect(query.merge_with(filter_attr => [])).to eq query
          end
        end
      end

      it "uses only the tiebreaking sort clauses when merging two queries that have an empty sort", covers: :sort do
        merged = merge(
          {sort: [], individual_docs_needed: true},
          {sort: [], individual_docs_needed: true}
        )

        expect(datastore_body_of(merged)).to include_sort_with_tiebreaker
      end

      it "does not use tiebreaking sort clauses when any of the two queries already specifies them", covers: :sort do
        merged = merge(
          {sort: [{"id" => {"order" => "desc"}}], individual_docs_needed: true},
          {sort: [], individual_docs_needed: true}
        )

        expect(datastore_body_of(merged)).to include(sort: [{"id" => {"order" => "desc", "missing" => "_last"}}])
      end

      it "uses the `sort` value from either query when only one of them has a value", covers: :sort do
        merged = merge(
          {sort: [{created_at: {"order" => "asc"}}], individual_docs_needed: true},
          {sort: [], individual_docs_needed: true}
        )

        expect(datastore_body_of(merged)).to include_sort_with_tiebreaker(created_at: {"order" => "asc"})
      end

      it "uses the `sort` value from the `merge_with` argument when both queries have a `sort` value and logs a warning", covers: :sort do
        query = new_query(sort: [{created_at: {"order" => "asc"}}], individual_docs_needed: true)
        merged = nil

        expect {
          merged = query.merge_with(
            sort: [{created_at: {"order" => "desc"}}],
            individual_docs_needed: true
          )
        }.to log a_string_including("Tried to merge conflicting values of `sort`")

        expect(datastore_body_of(merged)).to include_sort_with_tiebreaker(created_at: {"order" => "desc"})
      end

      it "uses one of the `sort` values when `sort` values are the same and does not log a warning", covers: :sort do
        merged = merge(
          {sort: [{created_at: {"order" => "asc"}}], individual_docs_needed: true},
          {sort: [{created_at: {"order" => "asc"}}], individual_docs_needed: true}
        )
        expect(datastore_body_of(merged)).to include_sort_with_tiebreaker(created_at: {"order" => "asc"})
      end

      it "maintains a `document_pagination` value of `{}` when merging two queries that have `{}` for `document_pagination`", covers: :document_pagination do
        merged = merge(
          {document_pagination: {}},
          {document_pagination: {}}
        )
        expect(merged.document_pagination).to eq({})
      end

      it "uses the `document_pagination` value from either query when only one of them has a value", covers: :document_pagination do
        merged = merge(
          {document_pagination: {first: 2}},
          {document_pagination: {}}
        )
        expect(merged.document_pagination).to eq({first: 2})
      end

      it "uses the `document_pagination` value from the `merge_with` argument when both queries have a `document_pagination` value and logs a warning", covers: :document_pagination do
        query = new_query(document_pagination: {first: 2})
        merged = nil

        expect {
          merged = query.merge_with(document_pagination: {first: 5})
        }.to log a_string_including("Tried to merge conflicting values of `document_pagination`")

        expect(merged.document_pagination).to eq({first: 5})
      end

      it "uses one of the `document_pagination` values when `document_pagination` values are the same and does not log a warning", covers: :document_pagination do
        merged = merge(
          {document_pagination: {first: 10}},
          {document_pagination: {first: 10}}
        )
        expect(merged.document_pagination).to eq({first: 10})
      end

      it "multiplies the `size_multiplier` when merging", covers: :size_multiplier do
        merged = merge({size_multiplier: 1}, {size_multiplier: 1})
        expect(merged.size_multiplier).to eq(1)

        merged = merge({size_multiplier: 5}, {size_multiplier: 1})
        expect(merged.size_multiplier).to eq(5)

        merged = merge({size_multiplier: 2}, {size_multiplier: 7})
        expect(merged.size_multiplier).to eq(14)
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

        merged = merge(
          {aggregations: {"a1" => agg1, "a3" => agg3}},
          {aggregations: {"a2" => agg2, "a3" => agg3}}
        )

        expect(merged.aggregations).to eq({
          "a1" => agg1,
          "a2" => agg2,
          "a3" => agg3
        })
      end

      it "correctly merges requested fields from multiple queries by concatenating and de-duplicating them", covers: :requested_fields do
        expect {
          merged = merge(
            {requested_fields: ["a", "b"]},
            {requested_fields: ["b", "c"]}
          )
          expect(merged.requested_fields).to contain_exactly("a", "b", "c")
        }.to avoid_logging_warnings
      end

      it "sets `request_all_fields` to `true` if it is set on either query", covers: :request_all_fields do
        merged = merge(
          {request_all_fields: true},
          {request_all_fields: false}
        )
        expect(merged.request_all_fields).to be true
      end

      it "sets `request_all_fields` to `true` if it is set on both queries", covers: :request_all_fields do
        merged = merge(
          {request_all_fields: true},
          {request_all_fields: true}
        )
        expect(merged.request_all_fields).to be true
      end

      it "sets `request_all_fields` to `false` if it is set to false on both queries", covers: :request_all_fields do
        merged = merge(
          {request_all_fields: false},
          {request_all_fields: false}
        )
        expect(merged.request_all_fields).to be false
      end

      it "correctly merges requested highlights from multiple queries by concatenating and de-duplicating them", covers: :requested_highlights do
        merged = merge(
          {requested_highlights: ["a", "b"]},
          {requested_highlights: ["b", "c"]}
        )
        expect(merged.requested_highlights).to contain_exactly("a", "b", "c")
      end

      it "sets `request_all_highlights` to `true` if it is set on either query", covers: :request_all_highlights do
        merged = merge(
          {request_all_highlights: true},
          {request_all_highlights: false}
        )
        expect(merged.request_all_highlights).to be true
      end

      it "sets `request_all_highlights` to `true` if it is set on both queries", covers: :request_all_highlights do
        merged = merge(
          {request_all_highlights: true},
          {request_all_highlights: true}
        )
        expect(merged.request_all_highlights).to be true
      end

      it "sets `request_all_highlights` to `false` if it is set to false on both queries", covers: :request_all_highlights do
        merged = merge(
          {request_all_highlights: false},
          {request_all_highlights: false}
        )
        expect(merged.request_all_highlights).to be false
      end

      it "sets `individual_docs_needed` to `true` if it is set on either query", covers: :individual_docs_needed do
        merged = merge(
          {individual_docs_needed: true},
          {individual_docs_needed: false}
        )
        expect(merged.individual_docs_needed).to be true
      end

      it "sets `individual_docs_needed` to `false` if it is set to `false` on both queries", covers: :individual_docs_needed do
        merged = merge(
          {individual_docs_needed: false},
          {individual_docs_needed: false}
        )
        expect(merged.individual_docs_needed).to be false
      end

      it "sets `individual_docs_needed` to `true` if specific fields are requested", covers: :individual_docs_needed do
        merged = merge(
          {individual_docs_needed: false},
          {requested_fields: ["name"]}
        )
        expect(merged.individual_docs_needed).to be true
      end

      it "sets `individual_docs_needed` to `true` if all fields are requested", covers: :individual_docs_needed do
        merged = merge(
          {individual_docs_needed: false},
          {request_all_fields: true}
        )
        expect(merged.individual_docs_needed).to be true
      end

      it "sets `individual_docs_needed` to `true` if specific highlights are requested", covers: :individual_docs_needed do
        merged = merge(
          {individual_docs_needed: false},
          {requested_highlights: ["name"]}
        )
        expect(merged.individual_docs_needed).to be true
      end

      it "sets `individual_docs_needed` to `true` if all highlights are requested", covers: :individual_docs_needed do
        merged = merge(
          {individual_docs_needed: false},
          {request_all_highlights: true}
        )
        expect(merged.individual_docs_needed).to be true
      end

      it "sets `total_document_count_needed` to `true` if it is set on either query", covers: :total_document_count_needed do
        merged = merge(
          {total_document_count_needed: true},
          {total_document_count_needed: false}
        )
        expect(merged.total_document_count_needed).to be true
      end

      it "sets `total_document_count_needed` to `false` if it is set to `false` on both queries", covers: :total_document_count_needed do
        merged = merge(
          {total_document_count_needed: false},
          {total_document_count_needed: false}
        )
        expect(merged.total_document_count_needed).to be false
      end

      it "forces `total_document_count_needed` to `true` if either query has an aggregation query that requires it", covers: :total_document_count_needed do
        merged = merge(
          {total_document_count_needed: false, aggregations: {"agg" => aggregation_query_of(needs_doc_count: true)}},
          {total_document_count_needed: false}
        )
        expect(merged.total_document_count_needed).to be true
      end

      it "does not force `total_document_count_needed` to `true` if the aggregations query has groupings", covers: :total_document_count_needed do
        merged = merge(
          {
            total_document_count_needed: false,
            aggregations: {"agg" => aggregation_query_of(
              needs_doc_count: true,
              groupings: [field_term_grouping_of("age")]
            )}
          },
          {total_document_count_needed: false}
        )
        expect(merged.total_document_count_needed).to be false
      end

      it "prefers a set `monotonic_clock_deadline` value to an unset one", covers: :monotonic_clock_deadline do
        merged = merge(
          {monotonic_clock_deadline: 5000},
          {monotonic_clock_deadline: nil}
        )
        expect(merged.monotonic_clock_deadline).to eq 5000
      end

      it "prefers the shorter `monotonic_clock_deadline` value so that we can default to an application config setting, " \
         "and override it with a shorter deadline", covers: :monotonic_clock_deadline do
        merged = merge(
          {monotonic_clock_deadline: 3000},
          {monotonic_clock_deadline: 6000}
        )
        expect(merged.monotonic_clock_deadline).to eq 3000
      end

      it "leaves `monotonic_clock_deadline` unset if unset on both source queries", covers: :monotonic_clock_deadline do
        merged = merge(
          {monotonic_clock_deadline: nil},
          {monotonic_clock_deadline: nil}
        )
        expect(merged.monotonic_clock_deadline).to eq nil
      end

      def filter_datastore_with(*filters)
        # `filter` uses the datastore's filtering context
        include(query: {bool: {filter: filters}})
      end

      def include_sort_with_tiebreaker(*sort_clauses)
        include(sort: sort_list_with_missing_option_for(*sort_clauses))
      end

      def merge(query_attrs1, query_attrs2)
        query1 = new_query(**query_attrs1)
        merged_2_into_1 = query1.merge_with(**query_attrs2)

        query2 = new_query(**query_attrs2)
        merged_1_into_2 = query2.merge_with(**query_attrs1)

        # Merge order should never matter.
        expect(merged_1_into_2).to eq(merged_2_into_1)

        # Shouldn't matter which we return since we've verified they are equal.
        merged_2_into_1
      end
    end
  end
end
