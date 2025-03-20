# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require_relative "datastore_aggregation_query_integration_support"
require "elastic_graph/graphql/aggregation/resolvers/relay_connection_builder"

module ElasticGraph
  class GraphQL
    RSpec.describe DatastoreQuery, "aggregations" do
      include_context "DatastoreAggregationQueryIntegrationSupport"

      before do
        index_into(
          graphql,
          build(:widget, amount_cents: 500, name: "Type 1", created_at: "2019-06-01T12:02:20Z"),
          build(:widget, amount_cents: 200, name: "Type 2", created_at: "2019-06-02T13:03:30Z"),
          build(:widget, amount_cents: 200, name: "Type 2", created_at: "2019-07-04T14:04:40Z"),
          build(:widget, amount_cents: 100, name: "Type 3", created_at: "2019-07-03T12:02:59Z")
        )
      end

      it "can run multiple aggregations in a single query" do
        by_name = aggregation_query_of(name: "by_name", computations: [computation_of("amount_cents", :sum)], groupings: [field_term_grouping_of("name")])
        by_month = aggregation_query_of(name: "by_month", computations: [computation_of("amount_cents", :sum)], groupings: [date_histogram_grouping_of("created_at", "month")])
        just_sum = aggregation_query_of(name: "just_sum", computations: [computation_of("amount_cents", :sum)])
        min_and_max = aggregation_query_of(name: "min_and_max", computations: [computation_of("amount_cents", :min), computation_of("amount_cents", :max)])
        just_count = aggregation_query_of(name: "just_count", needs_doc_count: true)

        all_aggs = [by_name, by_month, just_sum, min_and_max, just_count]

        results = search_datastore(aggregations: [by_name, by_month, just_sum, min_and_max, just_count])

        agg_nodes_by_agg_name = all_aggs.to_h do |agg|
          connection = Aggregation::Resolvers::RelayConnectionBuilder.build_from_search_response(
            schema_element_names: graphql.runtime_metadata.schema_element_names,
            search_response: results,
            query: agg
          )

          [agg.name, connection.nodes]
        end
        expect(agg_nodes_by_agg_name.keys).to contain_exactly("by_name", "by_month", "just_sum", "min_and_max", "just_count")

        amount_cents_sum = aggregated_value_key_of("amount_cents", "sum")

        amount_cents_sum = amount_cents_sum.with(aggregation_name: "by_name")
        expect(agg_nodes_by_agg_name.fetch("by_name").map(&:bucket)).to eq [
          {amount_cents_sum.encode => {"value" => 500.0}, "doc_count" => 1, "key" => {"name" => "Type 1"}},
          {amount_cents_sum.encode => {"value" => 400.0}, "doc_count" => 2, "key" => {"name" => "Type 2"}},
          {amount_cents_sum.encode => {"value" => 100.0}, "doc_count" => 1, "key" => {"name" => "Type 3"}}
        ]

        amount_cents_sum = amount_cents_sum.with(aggregation_name: "by_month")
        expect(agg_nodes_by_agg_name.fetch("by_month").map(&:bucket)).to eq [
          {amount_cents_sum.encode => {"value" => 700.0}, "doc_count" => 2, "key" => {"created_at" => "2019-06-01T00:00:00.000Z"}},
          {amount_cents_sum.encode => {"value" => 300.0}, "doc_count" => 2, "key" => {"created_at" => "2019-07-01T00:00:00.000Z"}}
        ]

        amount_cents_sum = amount_cents_sum.with(aggregation_name: "just_sum")
        expect(agg_nodes_by_agg_name.fetch("just_sum").map(&:bucket)).to match [
          a_hash_including({amount_cents_sum.encode => {"value" => 1000.0}, "doc_count" => 4})
        ]

        amount_cents_sum = amount_cents_sum.with(aggregation_name: "min_and_max")
        expect(agg_nodes_by_agg_name.fetch("min_and_max").map(&:bucket)).to match [
          a_hash_including({
            "doc_count" => 4,
            amount_cents_sum.with(function_name: "max").encode => {"value" => 500.0},
            amount_cents_sum.with(function_name: "min").encode => {"value" => 100.0}
          })
        ]

        expect(agg_nodes_by_agg_name.fetch("just_count").map(&:bucket)).to match [
          a_hash_including({"doc_count" => 4})
        ]
      end

      it "can get aggregation computation results as a single bucket, regardless of how many are requested, but returns an empty list if 0 are requested" do
        aggregations = aggregation_query_of(computations: [
          computation_of("amount_cents", :sum),
          computation_of("amount_cents", :avg),
          computation_of("amount_cents", :min),
          computation_of("amount_cents", :max),
          computation_of("amount_cents", :cardinality)
        ])

        results0 = search_datastore_aggregations(with_updated_paginator(aggregations, first: 0), total_document_count_needed: true)
        results1 = search_datastore_aggregations(with_updated_paginator(aggregations, first: 1), total_document_count_needed: true)
        results10 = search_datastore_aggregations(with_updated_paginator(aggregations, first: 10), total_document_count_needed: true)

        agg_key = aggregated_value_key_of("amount_cents", nil)

        expect(results0).to be_empty
        expect(results1).to eq(results10).and contain_exactly(
          {
            "doc_count" => 4,
            "key" => {},
            agg_key.with(function_name: "sum").encode => {"value" => 1000.0},
            agg_key.with(function_name: "min").encode => {"value" => 100.0},
            agg_key.with(function_name: "avg").encode => {"value" => 250.0},
            agg_key.with(function_name: "max").encode => {"value" => 500.0},
            agg_key.with(function_name: "cardinality").encode => {"value" => 3}
          }
        )
      end

      it "can get multiple buckets for a single aggregation computation and grouping, respecting the requested page size" do
        aggregations = aggregation_query_of(
          computations: [computation_of("amount_cents", :sum)],
          groupings: [field_term_grouping_of("name")]
        )

        results0 = search_datastore_aggregations(with_updated_paginator(aggregations, first: 0))
        results1 = search_datastore_aggregations(with_updated_paginator(aggregations, first: 1))
        results3 = search_datastore_aggregations(with_updated_paginator(aggregations, first: 3))
        results10 = search_datastore_aggregations(with_updated_paginator(aggregations, first: 10))

        amount_cents_sum = aggregated_value_key_of("amount_cents", "sum")

        expected_aggs = [
          {"key" => {"name" => "Type 2"}, "doc_count" => 2, amount_cents_sum.encode => {"value" => 400.0}},
          {"key" => {"name" => "Type 1"}, "doc_count" => 1, amount_cents_sum.encode => {"value" => 500.0}},
          {"key" => {"name" => "Type 3"}, "doc_count" => 1, amount_cents_sum.encode => {"value" => 100.0}}
        ]

        expect(results0).to be_empty
        expect(results1).to eq([expected_aggs[0]]).or eq([expected_aggs[1]]).or eq([expected_aggs[2]])
        expect(results3).to eq(results10).and match_array(expected_aggs)
      end

      it "can get multiple buckets for multiple aggregation computations and groupings, respecting the requested page size" do
        aggregations = aggregation_query_of(
          computations: [computation_of("amount_cents", :sum), computation_of("amount_cents", :avg)],
          groupings: [date_histogram_grouping_of("created_at", "day"), field_term_grouping_of("name")]
        )

        results0 = search_datastore_aggregations(with_updated_paginator(aggregations, first: 0))
        results1 = search_datastore_aggregations(with_updated_paginator(aggregations, first: 1))
        results4 = search_datastore_aggregations(with_updated_paginator(aggregations, first: 4))
        results10 = search_datastore_aggregations(with_updated_paginator(aggregations, first: 10))

        amount_cents_sum = aggregated_value_key_of("amount_cents", "sum")
        amount_cents_avg = aggregated_value_key_of("amount_cents", "avg")

        expected_aggs = [
          {
            "key" => {
              "created_at" => "2019-06-01T00:00:00.000Z",
              "name" => "Type 1"
            },
            "doc_count" => 1,
            amount_cents_sum.encode => {"value" => 500.0},
            amount_cents_avg.encode => {"value" => 500.0}
          },
          {
            "key" => {
              "created_at" => "2019-06-02T00:00:00.000Z",
              "name" => "Type 2"
            },
            "doc_count" => 1,
            amount_cents_sum.encode => {"value" => 200.0},
            amount_cents_avg.encode => {"value" => 200.0}
          },
          {
            "key" => {
              "created_at" => "2019-07-03T00:00:00.000Z",
              "name" => "Type 3"
            },
            "doc_count" => 1,
            amount_cents_sum.encode => {"value" => 100.0},
            amount_cents_avg.encode => {"value" => 100.0}
          },
          {
            "key" => {
              "created_at" => "2019-07-04T00:00:00.000Z",
              "name" => "Type 2"
            },
            "doc_count" => 1,
            amount_cents_sum.encode => {"value" => 200.0},
            amount_cents_avg.encode => {"value" => 200.0}
          }
        ]

        expect(results0).to be_empty
        expect(results1).to eq([expected_aggs[0]]).or eq([expected_aggs[1]]).or eq([expected_aggs[2]]).or eq([expected_aggs[3]])
        expect(results4).to eq(results10).and match_array(expected_aggs)
      end

      it "returns correct results for an `as_day_of_week` grouping" do
        aggregations = aggregation_query_of(
          computations: [computation_of("amount_cents", :sum), computation_of("amount_cents", :avg)],
          groupings: [
            as_day_of_week_grouping_of("created_at", runtime_metadata: graphql.runtime_metadata, graphql_subfield: "as_day_of_week"),
            field_term_grouping_of("name")
          ]
        )

        results = search_datastore_aggregations(with_updated_paginator(aggregations))

        amount_cents_sum = aggregated_value_key_of("amount_cents", "sum")
        amount_cents_avg = aggregated_value_key_of("amount_cents", "avg")

        expected_aggs = [
          {
            "key" => {
              "created_at.as_day_of_week" => "SATURDAY",
              "name" => "Type 1"
            },
            "doc_count" => 1,
            amount_cents_sum.encode => {"value" => 500.0},
            amount_cents_avg.encode => {"value" => 500.0}
          },
          {
            "key" => {
              "created_at.as_day_of_week" => "SUNDAY",
              "name" => "Type 2"
            },
            "doc_count" => 1,
            amount_cents_sum.encode => {"value" => 200.0},
            amount_cents_avg.encode => {"value" => 200.0}
          },
          {
            "key" => {
              "created_at.as_day_of_week" => "WEDNESDAY",
              "name" => "Type 3"
            },
            "doc_count" => 1,
            amount_cents_sum.encode => {"value" => 100.0},
            amount_cents_avg.encode => {"value" => 100.0}
          },
          {
            "key" => {
              "created_at.as_day_of_week" => "THURSDAY",
              "name" => "Type 2"
            },
            "doc_count" => 1,
            amount_cents_sum.encode => {"value" => 200.0},
            amount_cents_avg.encode => {"value" => 200.0}
          }
        ]

        expect(results).to eq(results).and match_array(expected_aggs)
      end

      it "returns correct results for an `as_day_of_week` grouping with `time_zone` set" do
        aggregations = aggregation_query_of(
          computations: [computation_of("amount_cents", :sum), computation_of("amount_cents", :avg)],
          groupings: [
            as_day_of_week_grouping_of("created_at", time_zone: "Australia/Melbourne", runtime_metadata: graphql.runtime_metadata, graphql_subfield: "as_day_of_week")
          ]
        )

        results = search_datastore_aggregations(with_updated_paginator(aggregations))

        amount_cents_sum = aggregated_value_key_of("amount_cents", "sum")
        amount_cents_avg = aggregated_value_key_of("amount_cents", "avg")

        expected_aggs = [
          {
            "key" => {
              "created_at.as_day_of_week" => "SATURDAY"
            },
            "doc_count" => 1,
            amount_cents_sum.encode => {"value" => 500.0},
            amount_cents_avg.encode => {"value" => 500.0}
          },
          {
            "key" => {
              "created_at.as_day_of_week" => "SUNDAY"
            },
            "doc_count" => 1,
            amount_cents_sum.encode => {"value" => 200.0},
            amount_cents_avg.encode => {"value" => 200.0}
          },
          {
            "key" => {
              "created_at.as_day_of_week" => "WEDNESDAY"
            },
            "doc_count" => 1,
            amount_cents_sum.encode => {"value" => 100.0},
            amount_cents_avg.encode => {"value" => 100.0}
          },
          {
            "key" => {
              "created_at.as_day_of_week" => "FRIDAY"
            },
            "doc_count" => 1,
            amount_cents_sum.encode => {"value" => 200.0},
            amount_cents_avg.encode => {"value" => 200.0}
          }
        ]

        expect(results).to eq(results).and match_array(expected_aggs)
      end

      it "returns correct results for an `as_day_of_week` grouping with `offset_ms` set" do
        aggregations = aggregation_query_of(
          computations: [computation_of("amount_cents", :sum), computation_of("amount_cents", :avg)],
          groupings: [
            as_day_of_week_grouping_of("created_at", offset_ms: -86_400_000, runtime_metadata: graphql.runtime_metadata, graphql_subfield: "as_day_of_week")
          ]
        )

        results = search_datastore_aggregations(with_updated_paginator(aggregations))

        amount_cents_sum = aggregated_value_key_of("amount_cents", "sum")
        amount_cents_avg = aggregated_value_key_of("amount_cents", "avg")

        expected_aggs = [
          {
            "key" => {
              "created_at.as_day_of_week" => "FRIDAY"
            },
            "doc_count" => 1,
            amount_cents_sum.encode => {"value" => 500.0},
            amount_cents_avg.encode => {"value" => 500.0}
          },
          {
            "key" => {
              "created_at.as_day_of_week" => "SATURDAY"
            },
            "doc_count" => 1,
            amount_cents_sum.encode => {"value" => 200.0},
            amount_cents_avg.encode => {"value" => 200.0}
          },
          {
            "key" => {
              "created_at.as_day_of_week" => "TUESDAY"
            },
            "doc_count" => 1,
            amount_cents_sum.encode => {"value" => 100.0},
            amount_cents_avg.encode => {"value" => 100.0}
          },
          {
            "key" => {
              "created_at.as_day_of_week" => "WEDNESDAY"
            },
            "doc_count" => 1,
            amount_cents_sum.encode => {"value" => 200.0},
            amount_cents_avg.encode => {"value" => 200.0}
          }
        ]

        expect(results).to eq(results).and match_array(expected_aggs)
      end

      it "returns correct results for an `as_time_of_day` grouping with a :second `interval`" do
        aggregations = aggregation_query_of(
          computations: [computation_of("amount_cents", :sum), computation_of("amount_cents", :avg)],
          groupings: [
            as_time_of_day_grouping_of("created_at", "second", runtime_metadata: graphql.runtime_metadata, graphql_subfield: "as_time_of_day")
          ]
        )

        results = search_datastore_aggregations(with_updated_paginator(aggregations))

        amount_cents_sum = aggregated_value_key_of("amount_cents", "sum")
        amount_cents_avg = aggregated_value_key_of("amount_cents", "avg")

        expected_aggs = [
          {
            "key" => {
              "created_at.as_time_of_day" => "12:02:20"
            },
            "doc_count" => 1,
            amount_cents_sum.encode => {"value" => 500.0},
            amount_cents_avg.encode => {"value" => 500.0}
          },
          {
            "key" => {
              "created_at.as_time_of_day" => "12:02:59"
            },
            "doc_count" => 1,
            amount_cents_sum.encode => {"value" => 100.0},
            amount_cents_avg.encode => {"value" => 100.0}
          },
          {
            "key" => {
              "created_at.as_time_of_day" => "13:03:30"
            },
            "doc_count" => 1,
            amount_cents_sum.encode => {"value" => 200.0},
            amount_cents_avg.encode => {"value" => 200.0}
          },
          {
            "key" => {
              "created_at.as_time_of_day" => "14:04:40"
            },
            "doc_count" => 1,
            amount_cents_sum.encode => {"value" => 200.0},
            amount_cents_avg.encode => {"value" => 200.0}
          }
        ]

        expect(results).to eq(results).and match_array(expected_aggs)
      end

      it "returns correct results for an `as_time_of_day` grouping with a :minute `interval` and `offset` set" do
        aggregations = aggregation_query_of(
          computations: [computation_of("amount_cents", :sum), computation_of("amount_cents", :avg)],
          groupings: [
            as_time_of_day_grouping_of("created_at", "minute", offset_ms: 5_400_000, runtime_metadata: graphql.runtime_metadata, graphql_subfield: "as_time_of_day")
          ]
        )

        results = search_datastore_aggregations(with_updated_paginator(aggregations))

        amount_cents_sum = aggregated_value_key_of("amount_cents", "sum")
        amount_cents_avg = aggregated_value_key_of("amount_cents", "avg")

        expected_aggs = [
          {
            "key" => {
              "created_at.as_time_of_day" => "13:32:00"
            },
            "doc_count" => 2,
            amount_cents_sum.encode => {"value" => 600.0},
            amount_cents_avg.encode => {"value" => 300.0}
          },
          {
            "key" => {
              "created_at.as_time_of_day" => "14:33:00"
            },
            "doc_count" => 1,
            amount_cents_sum.encode => {"value" => 200.0},
            amount_cents_avg.encode => {"value" => 200.0}
          },
          {
            "key" => {
              "created_at.as_time_of_day" => "15:34:00"
            },
            "doc_count" => 1,
            amount_cents_sum.encode => {"value" => 200.0},
            amount_cents_avg.encode => {"value" => 200.0}
          }
        ]

        expect(results).to eq(results).and match_array(expected_aggs)
      end

      it "returns correct results for an `as_time_of_day` grouping with a :hour `interval` and `time_zone` set" do
        aggregations = aggregation_query_of(
          computations: [computation_of("amount_cents", :sum), computation_of("amount_cents", :avg)],
          groupings: [
            as_time_of_day_grouping_of("created_at", "hour", time_zone: "Australia/Melbourne", runtime_metadata: graphql.runtime_metadata, graphql_subfield: "as_time_of_day")
          ]
        )

        results = search_datastore_aggregations(with_updated_paginator(aggregations))

        amount_cents_sum = aggregated_value_key_of("amount_cents", "sum")
        amount_cents_avg = aggregated_value_key_of("amount_cents", "avg")

        expected_aggs = [
          {
            "key" => {
              "created_at.as_time_of_day" => "22:00:00"
            },
            "doc_count" => 2,
            amount_cents_sum.encode => {"value" => 600.0},
            amount_cents_avg.encode => {"value" => 300.0}
          },
          {
            "key" => {
              "created_at.as_time_of_day" => "23:00:00"
            },
            "doc_count" => 1,
            amount_cents_sum.encode => {"value" => 200.0},
            amount_cents_avg.encode => {"value" => 200.0}
          },
          {
            "key" => {
              "created_at.as_time_of_day" => "00:00:00"
            },
            "doc_count" => 1,
            amount_cents_sum.encode => {"value" => 200.0},
            amount_cents_avg.encode => {"value" => 200.0}
          }
        ]

        expect(results).to eq(results).and match_array(expected_aggs)
      end

      def with_updated_paginator(aggregation_query, **paginator_opts)
        aggregation_query.with(paginator: aggregation_query.paginator.with(**paginator_opts))
      end
    end
  end
end
