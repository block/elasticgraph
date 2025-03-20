# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require_relative "datastore_query_unit_support"
require "support/aggregations_helpers"

module ElasticGraph
  class GraphQL
    RSpec.describe DatastoreQuery, "aggregations" do
      include AggregationsHelpers
      include_context "DatastoreQueryUnitSupport"

      it "excludes `aggs` if `aggregations` is not given" do
        expect(datastore_body_of(new_query)).to exclude(:aggs)
      end

      it "excludes `aggs` if `aggregations` is empty" do
        expect(datastore_body_of(new_query(aggregations: {}))).to exclude(:aggs)
      end

      it "excludes `aggs` if `aggregations.size` is 0" do
        query = new_query(aggregations: [aggregation_query_of(
          computations: [computation_of("amountMoney", "amount", :sum)],
          groupings: [field_term_grouping_of("options", "size")],
          first: 0
        )])

        expect(datastore_body_of(query)).to exclude(:aggs)
      end

      it "populates `aggs` with a metric aggregation when given only computations in `aggregations`" do
        query = new_query(aggregations: [aggregation_query_of(
          name: "my_aggs",
          computations: [
            computation_of("amountMoney", "amount", :sum),
            computation_of("amountMoney", "amount", :avg)
          ]
        )])

        expect(datastore_body_of(query)).to include_aggs(
          aggregated_value_key_of("amountMoney", "amount", "sum", aggregation_name: "my_aggs") => {"sum" => {"field" => "amountMoney.amount"}},
          aggregated_value_key_of("amountMoney", "amount", "avg", aggregation_name: "my_aggs") => {"avg" => {"field" => "amountMoney.amount"}}
        )
      end

      it "uses the GraphQL query field names in computation aggregation keys when they differ from the field names in the index" do
        query = new_query(aggregations: [aggregation_query_of(
          name: "my_aggs",
          computations: [
            computation_of("amountMoney", "amount", :sum, field_names_in_graphql_query: ["amtOuter", "amtInner"]),
            computation_of("amountMoney", "amount", :avg, field_names_in_graphql_query: ["amtOuter", "amtInner"])
          ]
        )])

        expect(datastore_body_of(query)).to include_aggs(
          aggregated_value_key_of("amtOuter", "amtInner", "sum", aggregation_name: "my_aggs") => {"sum" => {"field" => "amountMoney.amount"}},
          aggregated_value_key_of("amtOuter", "amtInner", "avg", aggregation_name: "my_aggs") => {"avg" => {"field" => "amountMoney.amount"}}
        )
      end

      it "populates `aggs` with a composite aggregation when given only groupings in `aggregations`" do
        query = new_query(aggregations: [aggregation_query_of(name: "my_agg", first: 12, groupings: [
          field_term_grouping_of("options", "size"),
          field_term_grouping_of("options", "color"),
          date_histogram_grouping_of("created_at", "day", time_zone: "UTC")
        ])])

        expect(datastore_body_of(query)).to include_aggs("my_agg" => {"composite" => {
          "size" => 13, # add 1 so that we can detect if there are more results.
          "sources" => [
            {"options.size" => {"terms" => {"field" => "options.size", "missing_bucket" => true}}},
            {"options.color" => {"terms" => {"field" => "options.color", "missing_bucket" => true}}},
            {"created_at" => {"date_histogram" => {"field" => "created_at", "missing_bucket" => true, "calendar_interval" => "day", "format" => DATASTORE_DATE_TIME_FORMAT, "time_zone" => "UTC"}}}
          ]
        }})
      end

      it "populates `aggs` for `as_day_of_week` using a script" do
        query = new_query(aggregations: [aggregation_query_of(name: "my_agg", first: 12, groupings: [
          as_day_of_week_grouping_of("created_at", time_zone: "UTC", offset_ms: 10_800_000, script_id: "some_script_id")
        ])])

        expect(datastore_body_of(query)).to include_aggs("my_agg" => {"composite" => {
          "size" => 13, # add 1 so that we can detect if there are more results.
          "sources" => [
            {"created_at" => {"terms" => {"missing_bucket" => true, "script" => {"id" => "some_script_id", "params" => {"field" => "created_at", "offset_ms" => 10800000, "time_zone" => "UTC"}}}}}
          ]
        }})
      end

      it "populates `aggs` for `as_time_of_day` using a script" do
        query = new_query(aggregations: [aggregation_query_of(name: "my_agg", first: 12, groupings: [
          as_time_of_day_grouping_of("created_at", "hour", time_zone: "UTC", offset_ms: 10_800_000, script_id: "some_script_id")
        ])])

        expect(datastore_body_of(query)).to include_aggs("my_agg" => {"composite" => {
          "size" => 13, # add 1 so that we can detect if there are more results.
          "sources" => [
            {"created_at" => {"terms" => {"missing_bucket" => true, "script" => {"id" => "some_script_id", "params" => {"field" => "created_at", "offset_ms" => 10800000, "time_zone" => "UTC", "interval" => "hour"}}}}}
          ]
        }})
      end

      it "uses the GraphQL query field names in composite aggregation keys when they differ from the field names in the index" do
        query = new_query(aggregations: [aggregation_query_of(name: "my_agg", first: 12, groupings: [
          field_term_grouping_of("options", "size", field_names_in_graphql_query: ["opts", "the_size"]),
          field_term_grouping_of("options", "color", field_names_in_graphql_query: ["opts", "color"]),
          date_histogram_grouping_of("created_at", "day", time_zone: "UTC", field_names_in_graphql_query: ["the_created_at"])
        ])])

        expect(datastore_body_of(query)).to include_aggs("my_agg" => {"composite" => {
          "size" => 13, # add 1 so that we can detect if there are more results.
          "sources" => [
            {"opts.the_size" => {"terms" => {"field" => "options.size", "missing_bucket" => true}}},
            {"opts.color" => {"terms" => {"field" => "options.color", "missing_bucket" => true}}},
            {"the_created_at" => {"date_histogram" => {"field" => "created_at", "missing_bucket" => true, "calendar_interval" => "day", "format" => DATASTORE_DATE_TIME_FORMAT, "time_zone" => "UTC"}}}
          ]
        }})
      end

      it "populates `aggs` with a composite aggregation and a metric sub-aggregation when given both groupings and computations in `aggregations`" do
        query = new_query(aggregations: [aggregation_query_of(
          name: "agg2",
          computations: [computation_of("amountMoney", "amount", :sum)],
          groupings: [field_term_grouping_of("options", "size")],
          first: 17
        )])

        expect(datastore_body_of(query)).to include_aggs("agg2" => {
          "composite" => {
            "size" => 18, # add 1 so that we can detect if there are more results.
            "sources" => [
              {"options.size" => {"terms" => {"field" => "options.size", "missing_bucket" => true}}}
            ]
          },
          "aggs" => {
            aggregated_value_key_of("amountMoney", "amount", "sum", aggregation_name: "agg2") => {"sum" => {"field" => "amountMoney.amount"}}
          }
        })
      end

      it "supports multiple aggregations in a single query" do
        by_name = aggregation_query_of(name: "by_name", first: 3, computations: [computation_of("amount_cents", :sum)], groupings: [field_term_grouping_of("name")])
        by_month = aggregation_query_of(name: "by_month", first: 4, computations: [computation_of("amount_cents", :sum)], groupings: [date_histogram_grouping_of("created_at", "month", time_zone: "UTC")])
        just_sum = aggregation_query_of(name: "just_sum", computations: [computation_of("amount_cents", :sum)])
        min_and_max = aggregation_query_of(name: "min_and_max", computations: [computation_of("amount_cents", :min), computation_of("amount_cents", :max)])
        just_count = aggregation_query_of(name: "just_count", needs_doc_count: true)

        query = new_query(aggregations: [by_name, by_month, just_sum, min_and_max, just_count])

        # `track_total_hits: true` is from the `just_count` aggregation.
        expect(datastore_body_of(query)).to include(track_total_hits: true).and include_aggs({
          aggregated_value_key_of("amount_cents", "sum", aggregation_name: "just_sum") => {
            "sum" => {
              "field" => "amount_cents"
            }
          },
          aggregated_value_key_of("amount_cents", "min", aggregation_name: "min_and_max") => {
            "min" => {
              "field" => "amount_cents"
            }
          },
          aggregated_value_key_of("amount_cents", "max", aggregation_name: "min_and_max") => {
            "max" => {
              "field" => "amount_cents"
            }
          },
          "by_month" => {
            "aggs" => {
              aggregated_value_key_of("amount_cents", "sum", aggregation_name: "by_month") => {
                "sum" => {
                  "field" => "amount_cents"
                }
              }
            },
            "composite" => {
              "size" => 5,
              "sources" => [
                {
                  "created_at" => {
                    "date_histogram" => {
                      "calendar_interval" => "month",
                      "field" => "created_at",
                      "format" => "strict_date_time",
                      "missing_bucket" => true,
                      "time_zone" => "UTC"
                    }
                  }
                }
              ]
            }
          },
          "by_name" => {
            "aggs" => {
              aggregated_value_key_of("amount_cents", "sum", aggregation_name: "by_name") => {
                "sum" => {
                  "field" => "amount_cents"
                }
              }
            },
            "composite" => {
              "size" => 4,
              "sources" => [
                {
                  "name" => {
                    "terms" => {
                      "field" => "name",
                      "missing_bucket" => true
                    }
                  }
                }
              ]
            }
          }
        })
      end

      def include_aggs(aggs)
        include(aggs: aggs)
      end

      def aggregated_value_key_of(...)
        super.encode
      end
    end
  end
end
