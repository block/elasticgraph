# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require_relative "aggregation_resolver_support"

module ElasticGraph
  class GraphQL
    module Aggregation
      RSpec.describe Resolvers, "for aggregations (without sub-aggregations)" do
        include_context "aggregation resolver support"

        it "resolves an ungrouped aggregation query just requesting the count" do
          response = resolve_target_nodes(<<~QUERY, aggs: nil, hit_count: 17)
            target: widget_aggregations {
              nodes {
                count
              }
            }
          QUERY

          expect(response).to eq [{"count" => 17}]
        end

        it "resolves a simple grouped aggregation query just requesting the count" do
          target_buckets = [
            {"key" => {"name" => "foo"}, "doc_count" => 2},
            {"key" => {"name" => "bar"}, "doc_count" => 7}
          ]

          response = resolve_target_nodes(<<~QUERY, target_buckets: target_buckets)
            target: widget_aggregations {
              nodes {
                grouped_by { name }
                count
              }
            }
          QUERY

          expect(response).to eq [
            {
              "grouped_by" => {"name" => "foo"},
              "count" => 2
            },
            {
              "grouped_by" => {"name" => "bar"},
              "count" => 7
            }
          ]
        end

        it "resolves nested `grouped_by` fields" do
          target_buckets = [
            {"key" => {"name" => "foo", "options.color" => "GREEN", "options.size" => "LARGE"}, "doc_count" => 2},
            {"key" => {"name" => "bar", "options.color" => "RED", "options.size" => "SMALL"}, "doc_count" => 7}
          ]

          response = resolve_target_nodes(<<~QUERY, target_buckets: target_buckets)
            target: widget_aggregations {
              nodes {
                grouped_by {
                  name
                  options {
                    color
                    size
                  }
                }
                count
              }
            }
          QUERY

          expect(response).to eq [
            {
              "grouped_by" => {"name" => "foo", "options" => {"color" => "GREEN", "size" => "LARGE"}},
              "count" => 2
            },
            {
              "grouped_by" => {"name" => "bar", "options" => {"color" => "RED", "size" => "SMALL"}},
              "count" => 7
            }
          ]
        end

        it "uses the GraphQL query field name rather than the `name_in_index` for the aggregation bucket keys" do
          target_buckets = [
            {"key" => {"workspace_id2" => "foo", "the_opts.the_sighs" => "SMALL"}, "doc_count" => 2},
            {"key" => {"workspace_id2" => "bar", "the_opts.the_sighs" => "LARGE"}, "doc_count" => 7}
          ]

          response = resolve_target_nodes(<<~QUERY, target_buckets: target_buckets)
            target: widget_aggregations {
              nodes {
                grouped_by {
                  workspace_id2: workspace_id
                  the_opts: the_options {
                    the_sighs: the_size
                  }
                }
                count
              }
            }
          QUERY

          expect(response).to eq [
            {
              "grouped_by" => {"workspace_id2" => "foo", "the_opts" => {"the_sighs" => "SMALL"}},
              "count" => 2
            },
            {
              "grouped_by" => {"workspace_id2" => "bar", "the_opts" => {"the_sighs" => "LARGE"}},
              "count" => 7
            }
          ]
        end

        it "resolves `count`, `aggregated_values` and `grouped_by` fields for a completely empty response that we get querying a rollover index pattern and no concrete indexes yet exist that match the pattern" do
          response = resolve_target_nodes(<<~QUERY, aggs: nil)
            target: widget_aggregations {
              nodes {
                count

                aggregated_values {
                  amount_cents { exact_sum }
                  cost {
                    amount_cents { exact_max }
                  }
                }

                grouped_by {
                  name
                  options {
                    color
                    size
                  }
                }
              }
            }
          QUERY

          expect(response).to eq [{
            "grouped_by" => {
              "name" => nil,
              "options" => {
                "color" => nil,
                "size" => nil
              }
            },
            "count" => 0,
            "aggregated_values" => {
              "amount_cents" => {"exact_sum" => 0},
              "cost" => {"amount_cents" => {"exact_max" => nil}}
            }
          }]
        end

        it "resolves `count`, `aggregated_values` and `grouped_by` fields for a completely empty response when field aliases are used" do
          response = resolve_target_nodes(<<~QUERY, aggs: nil)
            target: widget_aggregations {
              nodes {
                count

                aggregated_values {
                  ac: amount_cents { exact_sum }
                  c: cost {
                    amount_cents { exact_max }
                  }
                }

                grouped_by {
                  nm: name
                  opt: options {
                    c: color
                    s: size
                  }
                }
              }
            }
          QUERY

          expect(response).to eq [{
            "grouped_by" => {
              "nm" => nil,
              "opt" => {
                "c" => nil,
                "s" => nil
              }
            },
            "count" => 0,
            "aggregated_values" => {
              "ac" => {"exact_sum" => 0},
              "c" => {"amount_cents" => {"exact_max" => nil}}
            }
          }]
        end

        it "resolves an ungrouped aggregation query containing aggregated values" do
          aggs = {
            aggregated_value_key_of("amount_cents", "exact_sum") => {"value" => 900.0},
            aggregated_value_key_of("cost", "amount_cents", "exact_max") => {"value" => 400.0},
            aggregated_value_key_of("cost", "amount_cents", "exact_sum") => {"value" => 1400.0},
            aggregated_value_key_of("cost", "currency", "approximate_distinct_value_count") => {"value" => 5.0}
          }

          response = resolve_target_nodes(<<~QUERY, aggs: aggs)
            target: widget_aggregations {
              nodes {
                aggregated_values {
                  amount_cents { exact_sum }
                  cost {
                    amount_cents {
                      exact_max
                      exact_sum
                    }
                    currency { approximate_distinct_value_count }
                  }
                }
              }
            }
          QUERY

          expect(response).to eq [
            {
              "aggregated_values" => {
                "amount_cents" => {"exact_sum" => 900},
                "cost" => {
                  "amount_cents" => {
                    "exact_max" => 400,
                    "exact_sum" => 1400
                  },
                  "currency" => {
                    "approximate_distinct_value_count" => 5
                  }
                }
              }
            }
          ]
        end

        it "uses GraphQL field aliases when resolving `aggregated_values` subfields" do
          aggs = {
            aggregated_value_key_of("amount_cents", "exact_sum") => {"value" => 900.0},
            aggregated_value_key_of("cost", "amt_cts", "exact_max") => {"value" => 400.0},
            aggregated_value_key_of("cost", "amt_cts", "exact_sum") => {"value" => 1400.0},
            aggregated_value_key_of("cost", "currency", "approximate_distinct_value_count") => {"value" => 5.0}
          }

          response = resolve_target_nodes(<<~QUERY, aggs: aggs)
            target: widget_aggregations {
              nodes {
                aggregated_values {
                  amount_cents { exact_sum }
                  cost {
                    amt_cts: amount_cents {
                      exact_max
                      exact_sum
                    }
                    currency { approximate_distinct_value_count }
                  }
                }
              }
            }
          QUERY

          expect(response).to eq [
            {
              "aggregated_values" => {
                "amount_cents" => {"exact_sum" => 900},
                "cost" => {
                  "amt_cts" => {
                    "exact_max" => 400,
                    "exact_sum" => 1400
                  },
                  "currency" => {
                    "approximate_distinct_value_count" => 5
                  }
                }
              }
            }
          ]
        end

        it "resolves aggregated Date/DateTime/LocalTime values" do
          aggs = {
            aggregated_value_key_of("created_at", "exact_min") => {"value" => 1696854612000.0, "value_as_string" => "2023-10-09T12:30:12.000Z"},
            aggregated_value_key_of("created_at", "exact_max") => {"value" => 1704792612000.0, "value_as_string" => "2024-01-09T09:30:12.000Z"},
            aggregated_value_key_of("created_at", "approximate_avg") => {"value" => 1701039012530.0, "value_as_string" => "2023-11-26T22:50:12.530Z"},
            aggregated_value_key_of("created_on", "exact_min") => {"value" => 1696809600000.0, "value_as_string" => "2023-10-09"},
            aggregated_value_key_of("created_on", "exact_max") => {"value" => 1704758400000.0, "value_as_string" => "2024-01-09"},
            aggregated_value_key_of("created_on", "approximate_avg") => {"value" => 1700985600000.0, "value_as_string" => "2023-11-26"},
            aggregated_value_key_of("created_at_time_of_day", "exact_min") => {"value" => 34212000.0, "value_as_string" => "09:30:12"},
            aggregated_value_key_of("created_at_time_of_day", "exact_max") => {"value" => 81012000.0, "value_as_string" => "22:30:12"},
            aggregated_value_key_of("created_at_time_of_day", "approximate_avg") => {"value" => 53412000.0, "value_as_string" => "14:50:12"},
            aggregated_value_key_of("created_on", "approximate_distinct_value_count") => {"value" => 3.0},
            aggregated_value_key_of("created_at", "approximate_distinct_value_count") => {"value" => 3.0},
            aggregated_value_key_of("created_at_time_of_day", "approximate_distinct_value_count") => {"value" => 3.0}
          }

          response = resolve_target_nodes(<<~QUERY, aggs: aggs)
            target: widget_aggregations {
              nodes {
                aggregated_values {
                  created_at { exact_min, exact_max, approximate_avg, approximate_distinct_value_count }
                  created_on { exact_min, exact_max, approximate_avg, approximate_distinct_value_count }
                  created_at_time_of_day { exact_min, exact_max, approximate_avg, approximate_distinct_value_count }
                }
              }
            }
          QUERY

          expect(response).to eq [
            {
              "aggregated_values" => {
                "created_at" => {
                  "exact_min" => "2023-10-09T12:30:12.000Z",
                  "exact_max" => "2024-01-09T09:30:12.000Z",
                  "approximate_avg" => "2023-11-26T22:50:12.530Z",
                  "approximate_distinct_value_count" => 3
                },
                "created_on" => {
                  "exact_min" => "2023-10-09",
                  "exact_max" => "2024-01-09",
                  "approximate_avg" => "2023-11-26",
                  "approximate_distinct_value_count" => 3
                },
                "created_at_time_of_day" => {
                  "exact_min" => "09:30:12",
                  "exact_max" => "22:30:12",
                  "approximate_avg" => "14:50:12",
                  "approximate_distinct_value_count" => 3
                }
              }
            }
          ]
        end

        it "resolves legacy aggregated Date/DateTime/LocalTime values" do
          aggs = {
            aggregated_value_key_of("created_at_legacy", "exact_min") => {"value" => 1696854612000.0, "value_as_string" => "2023-10-09T12:30:12.000Z"},
            aggregated_value_key_of("created_at_legacy", "exact_max") => {"value" => 1704792612000.0, "value_as_string" => "2024-01-09T09:30:12.000Z"},
            aggregated_value_key_of("created_at_legacy", "approximate_avg") => {"value" => 1701039012530.0, "value_as_string" => "2023-11-26T22:50:12.530Z"},
            aggregated_value_key_of("created_on_legacy", "exact_min") => {"value" => 1696809600000.0, "value_as_string" => "2023-10-09"},
            aggregated_value_key_of("created_on_legacy", "exact_max") => {"value" => 1704758400000.0, "value_as_string" => "2024-01-09"},
            aggregated_value_key_of("created_on_legacy", "approximate_avg") => {"value" => 1700985600000.0, "value_as_string" => "2023-11-26"},
            aggregated_value_key_of("created_at_time_of_day", "exact_min") => {"value" => 34212000.0, "value_as_string" => "09:30:12"},
            aggregated_value_key_of("created_at_time_of_day", "exact_max") => {"value" => 81012000.0, "value_as_string" => "22:30:12"},
            aggregated_value_key_of("created_at_time_of_day", "approximate_avg") => {"value" => 53412000.0, "value_as_string" => "14:50:12"},
            aggregated_value_key_of("created_on_legacy", "approximate_distinct_value_count") => {"value" => 3.0},
            aggregated_value_key_of("created_at_legacy", "approximate_distinct_value_count") => {"value" => 3.0},
            aggregated_value_key_of("created_at_time_of_day", "approximate_distinct_value_count") => {"value" => 3.0}
          }

          response = resolve_target_nodes(<<~QUERY, aggs: aggs)
            target: widget_aggregations {
              nodes {
                aggregated_values {
                  created_at_legacy { exact_min, exact_max, approximate_avg, approximate_distinct_value_count }
                  created_on_legacy { exact_min, exact_max, approximate_avg, approximate_distinct_value_count }
                  created_at_time_of_day { exact_min, exact_max, approximate_avg, approximate_distinct_value_count }
                }
              }
            }
          QUERY

          expect(response).to eq [
            {
              "aggregated_values" => {
                "created_at_legacy" => {
                  "exact_min" => "2023-10-09T12:30:12.000Z",
                  "exact_max" => "2024-01-09T09:30:12.000Z",
                  "approximate_avg" => "2023-11-26T22:50:12.530Z",
                  "approximate_distinct_value_count" => 3
                },
                "created_on_legacy" => {
                  "exact_min" => "2023-10-09",
                  "exact_max" => "2024-01-09",
                  "approximate_avg" => "2023-11-26",
                  "approximate_distinct_value_count" => 3
                },
                "created_at_time_of_day" => {
                  "exact_min" => "09:30:12",
                  "exact_max" => "22:30:12",
                  "approximate_avg" => "14:50:12",
                  "approximate_distinct_value_count" => 3
                }
              }
            }
          ]
        end

        it "resolves the `cursor` on an ungrouped aggregation" do
          response = resolve_target_nodes(<<~QUERY, aggs: nil, path: ["data", "target", "edges"])
            target: widget_aggregations {
              edges {
                cursor
              }
            }
          QUERY

          expect(response).to eq [{"cursor" => DecodedCursor::SINGLETON.encode}]
        end

        it "resolves the `cursor` on a grouped aggregation" do
          target_buckets = [
            {"key" => {"name" => "foo"}},
            {"key" => {"name" => "bar"}}
          ]

          response = resolve_target_nodes(<<~QUERY, target_buckets: target_buckets, path: ["data", "target", "edges"])
            target: widget_aggregations {
              edges {
                cursor
                node {
                  grouped_by { name }
                }
              }
            }
          QUERY

          expect(response).to eq [
            {
              "cursor" => DecodedCursor.new({"name" => "foo"}).encode,
              "node" => {"grouped_by" => {"name" => "foo"}}
            },
            {
              "cursor" => DecodedCursor.new({"name" => "bar"}).encode,
              "node" => {"grouped_by" => {"name" => "bar"}}
            }
          ]
        end

        def aggregated_value_key_of(*field_path, function_name, aggregation_name: "target")
          super(*field_path, function_name, aggregation_name: "target").encode
        end
      end
    end
  end
end
