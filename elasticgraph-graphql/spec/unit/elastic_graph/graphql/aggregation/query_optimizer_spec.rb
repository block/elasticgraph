# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphql/aggregation/query_optimizer"
require "support/aggregations_helpers"

module ElasticGraph
  class GraphQL
    module Aggregation
      RSpec.describe QueryOptimizer, ".optimize_queries", :capture_logs do
        include AggregationsHelpers

        let(:graphql) { build_graphql }
        let(:widgets_def) { graphql.datastore_core.index_definitions_by_name.fetch("widgets") }
        let(:components_def) { graphql.datastore_core.index_definitions_by_name.fetch("components") }
        let(:executed_queries) { [] }

        it "merges aggregations queries together when they only differ in their `aggs`, allowing us to send fewer requests to the datastore" do
          by_size_agg = aggregation_query_of(
            name: "by_size",
            computations: [computation_of("amountMoney", "amount", :sum)],
            groupings: [field_term_grouping_of("options", "size")]
          )
          by_color_agg = aggregation_query_of(
            name: "by_color",
            computations: [computation_of("amountMoney", "amount", :sum)],
            groupings: [field_term_grouping_of("options", "color")]
          )
          just_sum_agg = aggregation_query_of(
            name: "just_sum",
            computations: [computation_of("amountMoney", "amount", :sum)]
          )

          base_query = new_query(filters: [{"age" => {"equal_to_any_of" => [0]}}])

          by_size = with_aggs(base_query, [by_size_agg])
          by_color = with_aggs(base_query, [by_color_agg])
          just_sum = with_aggs(base_query, [just_sum_agg])

          results_by_query = optimize_queries(by_size, by_color, just_sum)

          expect(executed_queries).to contain_exactly(with_aggs(base_query, [
            with_prefix(by_size_agg, 1),
            with_prefix(by_color_agg, 2),
            with_prefix(just_sum_agg, 3)
          ]))
          expect(results_by_query.keys).to contain_exactly(by_size, by_color, just_sum)
          expect(results_by_query[by_size]).to eq(raw_response_with_aggregations(build_agg_response_for(by_size_agg)))
          expect(results_by_query[by_color]).to eq(raw_response_with_aggregations(build_agg_response_for(by_color_agg)))
          expect(results_by_query[just_sum]).to eq(raw_response_with_aggregations(build_agg_response_for(just_sum_agg)))
          expect(merged_query_logs.size).to eq(1)
          expect(merged_query_logs.first).to include(
            "query_count" => 3,
            "aggregation_count" => 3,
            "aggregation_names" => ["1_by_size", "2_by_color", "3_just_sum"]
          )
        end

        it "can handle duplicated aggregation names" do
          by_size_agg = aggregation_query_of(
            name: "my_agg",
            computations: [computation_of("amountMoney", "amount", :sum)],
            groupings: [field_term_grouping_of("options", "size")]
          )
          by_color_agg = aggregation_query_of(
            name: "my_agg",
            computations: [computation_of("amountMoney", "amount", :sum)],
            groupings: [field_term_grouping_of("options", "color")]
          )
          just_sum_agg = aggregation_query_of(
            name: "my_agg",
            computations: [computation_of("amountMoney", "amount", :sum)]
          )

          base_query = new_query(filters: [{"age" => {"equal_to_any_of" => [0]}}])

          by_size = with_aggs(base_query, [by_size_agg])
          by_color = with_aggs(base_query, [by_color_agg])
          just_sum = with_aggs(base_query, [just_sum_agg])

          results_by_query = optimize_queries(by_size, by_color, just_sum)

          expect(executed_queries).to contain_exactly(with_aggs(base_query, [
            with_prefix(by_size_agg, 1),
            with_prefix(by_color_agg, 2),
            with_prefix(just_sum_agg, 3)
          ]))
          expect(results_by_query.keys).to contain_exactly(by_size, by_color, just_sum)
          expect(results_by_query[by_size]).to eq(raw_response_with_aggregations(build_agg_response_for(by_size_agg)))
          expect(results_by_query[by_color]).to eq(raw_response_with_aggregations(build_agg_response_for(by_color_agg)))
          expect(results_by_query[just_sum]).to eq(raw_response_with_aggregations(build_agg_response_for(just_sum_agg)))
          expect(merged_query_logs.size).to eq(1)
          expect(merged_query_logs.first).to include(
            "query_count" => 3,
            "aggregation_count" => 3,
            "aggregation_names" => ["1_my_agg", "2_my_agg", "3_my_agg"]
          )
        end

        it "can merge non-aggregation queries that are identical as well" do
          q1 = new_query(filters: [{"age" => {"equal_to_any_of" => [0]}}])
          q2 = new_query(filters: [{"age" => {"equal_to_any_of" => [0]}}])
          expect(q1).to eq(q2)

          results_by_query = optimize_queries(q1, q2)

          expect(executed_queries).to contain_exactly(q1)
          expect(results_by_query[q1]).to eq build_response_for(q1)
          expect(results_by_query[q2]).to eq build_response_for(q2)
          expect(merged_query_logs.size).to eq(1)
          expect(merged_query_logs.first).to include(
            "query_count" => 2,
            "aggregation_count" => 0,
            "aggregation_names" => []
          )
        end

        it "keeps queries separate when they have non-aggregation differences" do
          optimize_queries(
            base_query = new_query(filters: [{"age" => {"equal_to_any_of" => [0]}}], individual_docs_needed: true),
            alt_filter = base_query.with(filters: [{"age" => {"equal_to_any_of" => [1]}}]),
            alt_pagination = base_query.with(document_pagination: {first: 1}),
            alt_individual_docs_needed = base_query.with(individual_docs_needed: !base_query.individual_docs_needed),
            alt_sort = base_query.with(sort: [{"age" => {"order" => "desc"}}]),
            alt_requested_fields = base_query.with(requested_fields: ["name"]),
            alt_index = base_query.with(search_index_definitions: [components_def])
          )

          expect(executed_queries).to contain_exactly(
            base_query,
            alt_filter,
            alt_pagination,
            alt_individual_docs_needed,
            alt_sort,
            alt_requested_fields,
            alt_index
          )

          expect(merged_query_logs).to be_empty
        end

        it "does not mess with the aggregation name when no merging happens" do
          by_size_agg = aggregation_query_of(
            name: "by_size",
            computations: [computation_of("amountMoney", "amount", :sum)],
            groupings: [field_term_grouping_of("options", "size")]
          )
          by_color_agg = aggregation_query_of(
            name: "by_color",
            computations: [computation_of("amountMoney", "amount", :sum)],
            groupings: [field_term_grouping_of("options", "color")]
          )

          base_query = new_query(filters: [{"age" => {"equal_to_any_of" => [0]}}])

          by_size = base_query.with(
            filters: [{"age" => {"equal_to_any_of" => [0]}}],
            aggregations: {by_size_agg.name => by_size_agg}
          )
          by_color = base_query.with(
            filters: [{"age" => {"equal_to_any_of" => [1]}}],
            aggregations: {by_color_agg.name => by_color_agg}
          )

          results_by_query = optimize_queries(by_size, by_color)

          expect(executed_queries).to contain_exactly(by_size, by_color)
          expect(results_by_query.keys).to contain_exactly(by_size, by_color)
          expect(results_by_query[by_size]).to eq(raw_response_with_aggregations(build_agg_response_for(by_size_agg)))
          expect(results_by_query[by_color]).to eq(raw_response_with_aggregations(build_agg_response_for(by_color_agg)))
          expect(merged_query_logs).to be_empty
        end

        it "returns an empty hash and never yields if given an empty list of queries" do
          expect { |probe|
            result = QueryOptimizer.optimize_queries([], &probe)
            expect(result).to eq({})
          }.not_to yield_control
        end

        def optimize_queries(*queries)
          QueryOptimizer.optimize_queries(queries) do |header_body_tuples_by_query|
            header_body_tuples_by_query.to_h do |query, _|
              executed_queries << query
              [query, build_response_for(query)]
            end
          end
        end

        def new_query(**options)
          graphql.datastore_query_builder.new_query(search_index_definitions: [widgets_def], **options)
        end

        def build_response_for(query)
          return DatastoreResponse::SearchResponse::RAW_EMPTY if query.aggregations.empty?

          aggregations = query.aggregations.values.map do |agg|
            build_agg_response_for(agg)
          end.reduce(:merge)

          raw_response_with_aggregations(aggregations)
        end

        def build_agg_response_for(agg)
          metrics = agg.computations.to_h do |comp|
            [comp.key(aggregation_name: agg.name), {"value" => 17}]
          end

          if agg.groupings.any?
            response_key = agg.groupings.to_h do |grouping|
              [grouping.key, "some-value"]
            end

            {agg.name => {"buckets" => [metrics.merge("key" => response_key)]}}
          else
            metrics
          end
        end

        def raw_response_with_aggregations(aggregations)
          DatastoreResponse::SearchResponse::RAW_EMPTY.merge("aggregations" => aggregations)
        end

        def merged_query_logs
          logged_jsons_of_type("AggregationQueryOptimizerMergedQueries")
        end

        def with_prefix(aggregation, num)
          aggregation.with(name: "#{num}_#{aggregation.name}")
        end

        def with_aggs(query, aggs)
          query.with(aggregations: aggs.to_h { |a| [a.name, a] })
        end
      end
    end
  end
end
