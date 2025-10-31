# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require_relative "aggregation_resolver_support"
require_relative "ungrouped_sub_aggregation_shared_examples"
require "support/sub_aggregation_support"

module ElasticGraph
  class GraphQL
    module Aggregation
      RSpec.describe Resolvers, "for sub-aggregations, when the `NonCompositeGroupingAdapter` adapter is used" do
        using SubAggregationRefinements
        include_context "aggregation resolver support"
        include_context "sub-aggregation support", Aggregation::NonCompositeGroupingAdapter
        it_behaves_like "ungrouped sub-aggregations"

        context "with `count_detail` fields and grouping" do
          it "indicates the count is exact when grouping only on date fields" do
            aggs = {
              "target:seasons_nested" => {
                "meta" => outer_meta({"buckets_path" => ["seasons_nested.started_at.as_date_time"]}),
                "doc_count" => 6,
                "seasons_nested.started_at.as_date_time" => {
                  "meta" => inner_date_meta("seasons_nested.started_at.as_date_time"),
                  "doc_count_error_upper_bound" => 0,
                  "sum_other_doc_count" => 0,
                  "buckets" => [
                    {
                      "key_as_string" => "2019-01-01T00:00:00.000Z",
                      "key" => 1546300800000,
                      "doc_count" => 3
                    }
                  ]
                }
              }.with_missing_value_bucket(0)
            }

            response = resolve_target_nodes(<<~QUERY, aggs: aggs)
              target: team_aggregations {
                nodes {
                  sub_aggregations {
                    seasons_nested {
                      nodes {
                        grouped_by { started_at { as_date_time(truncation_unit: YEAR) }}
                        count_detail {
                          approximate_value
                          exact_value
                          upper_bound
                        }
                      }
                    }
                  }
                }
              }
            QUERY

            expect(response.dig(0, "sub_aggregations", "seasons_nested", "nodes", 0, "count_detail")).to be_exactly_equal_to(3)
          end

          it "computes `exact_value` and `upper_bound` based on `doc_count_error_upper_bound` when available on a non-date grouping" do
            aggs = {
              "target:seasons_nested" => {
                "meta" => outer_meta({"buckets_path" => ["seasons_nested.year"]}),
                "doc_count" => 4,
                "seasons_nested.year" => {
                  "meta" => inner_terms_meta("seasons_nested.year"),
                  "doc_count_error_upper_bound" => 0,
                  "sum_other_doc_count" => 0,
                  "buckets" => [
                    {
                      "key" => 2020,
                      "doc_count" => 200,
                      "doc_count_error_upper_bound" => 7
                    },
                    {
                      "key" => 2021,
                      "doc_count" => 100,
                      "doc_count_error_upper_bound" => 0
                    }
                  ]
                }
              }.with_missing_value_bucket(5)
            }

            response = resolve_target_nodes(<<~QUERY, aggs: aggs)
              target: team_aggregations {
                nodes {
                  sub_aggregations {
                    seasons_nested {
                      nodes {
                        grouped_by { year }
                        count_detail {
                          approximate_value
                          exact_value
                          upper_bound
                        }
                      }
                    }
                  }
                }
              }
            QUERY

            expect(response.dig(0, "sub_aggregations", "seasons_nested", "nodes", 0, "count_detail")).to be_approximately_equal_to(200, with_upper_bound: 207)
            expect(response.dig(0, "sub_aggregations", "seasons_nested", "nodes", 1, "count_detail")).to be_exactly_equal_to(100)
            expect(response.dig(0, "sub_aggregations", "seasons_nested", "nodes", 2, "count_detail")).to be_exactly_equal_to(5)
          end

          def be_exactly_equal_to(count)
            eq({"approximate_value" => count, "exact_value" => count, "upper_bound" => count})
          end

          def be_approximately_equal_to(count, with_upper_bound:)
            eq({"approximate_value" => count, "exact_value" => nil, "upper_bound" => with_upper_bound})
          end
        end

        context "with grouping" do
          it "resolves all `page_info` fields" do
            query_with_first = lambda do |first|
              aggs = {
                "target:seasons_nested" => {
                  "meta" => outer_meta({"buckets_path" => ["seasons_nested.year"]}, size: first),
                  "doc_count" => 4,
                  "seasons_nested.year" => {
                    "meta" => inner_terms_meta("seasons_nested.year"),
                    "doc_count_error_upper_bound" => 0,
                    "sum_other_doc_count" => 0,
                    "buckets" => [
                      {
                        "key" => 2020,
                        "doc_count" => 2
                      },
                      {
                        "key" => 2019,
                        "doc_count" => 1
                      },
                      {
                        "key" => 2022,
                        "doc_count" => 1
                      }
                    ]
                  }
                }.with_missing_value_bucket(0)
              }

              resolve_target_nodes(<<~QUERY, aggs: aggs)
                target: team_aggregations {
                  nodes {
                    sub_aggregations {
                      seasons_nested(first: #{first}) {
                        page_info {
                          has_next_page
                          has_previous_page
                          start_cursor
                          end_cursor
                        }
                        nodes {
                          grouped_by { year }
                        }
                      }
                    }
                  }
                }
              QUERY
            end

            expect(query_with_first.call(3)).to match [
              {
                "sub_aggregations" => {
                  "seasons_nested" => {
                    "page_info" => an_object_matching({
                      "has_next_page" => false, # false since we only got 3 buckets (the requested amount)
                      "has_previous_page" => false,
                      "start_cursor" => /\w+/,
                      "end_cursor" => /\w+/
                    }),
                    "nodes" => [
                      {"grouped_by" => {"year" => 2020}},
                      {"grouped_by" => {"year" => 2019}},
                      {"grouped_by" => {"year" => 2022}}
                    ]
                  }
                }
              }
            ]

            expect(query_with_first.call(2)).to match [
              {
                "sub_aggregations" => {
                  "seasons_nested" => {
                    "page_info" => an_object_matching({
                      "has_next_page" => true, # true since we got more than the 1 bucket we requested
                      "has_previous_page" => false,
                      "start_cursor" => /\w+/,
                      "end_cursor" => /\w+/
                    }),
                    "nodes" => [
                      {"grouped_by" => {"year" => 2020}},
                      {"grouped_by" => {"year" => 2019}}
                    ]
                  }
                }
              }
            ]
          end

          it "resolves a sub-aggregation grouping on one non-date, non-boolean field" do
            aggs = {
              "target:seasons_nested" => {
                "meta" => outer_meta({"buckets_path" => ["seasons_nested.year"]}),
                "doc_count" => 4,
                "seasons_nested.year" => {
                  "meta" => inner_terms_meta("seasons_nested.year"),
                  "doc_count_error_upper_bound" => 0,
                  "sum_other_doc_count" => 0,
                  "buckets" => [
                    {
                      "key" => 2020,
                      "doc_count" => 2
                    },
                    {
                      "key" => 2019,
                      "doc_count" => 1
                    },
                    {
                      "key" => 2022,
                      "doc_count" => 1
                    }
                  ]
                }
              }.with_missing_value_bucket(0)
            }

            response = resolve_target_nodes(<<~QUERY, aggs: aggs)
              target: team_aggregations {
                nodes {
                  sub_aggregations {
                    seasons_nested {
                      nodes {
                        grouped_by { year }
                        count_detail { approximate_value }
                      }
                    }
                  }
                }
              }
            QUERY

            expect(response).to eq([{
              "sub_aggregations" => {
                "seasons_nested" => {
                  "nodes" => [
                    {"count_detail" => {"approximate_value" => 2}, "grouped_by" => {"year" => 2020}},
                    {"count_detail" => {"approximate_value" => 1}, "grouped_by" => {"year" => 2019}},
                    {"count_detail" => {"approximate_value" => 1}, "grouped_by" => {"year" => 2022}}
                  ]
                }
              }
            }])
          end

          it "resolves a sub-aggregation grouping on one boolean field" do
            aggs = {
              "target:seasons_nested" => {
                "meta" => outer_meta({"buckets_path" => ["seasons_nested.was_shortened"]}),
                "doc_count" => 6,
                "seasons_nested.was_shortened" => {
                  "meta" => inner_terms_meta("seasons_nested.was_shortened"),
                  "doc_count_error_upper_bound" => 0,
                  "sum_other_doc_count" => 0,
                  "buckets" => [
                    {
                      "key" => 0,
                      "key_as_string" => "false",
                      "doc_count" => 4,
                      "doc_count_error_upper_bound" => 0
                    },
                    {
                      "key" => 1,
                      "key_as_string" => "true",
                      "doc_count" => 2,
                      "doc_count_error_upper_bound" => 0
                    }
                  ]
                }
              }.with_missing_value_bucket(0)
            }

            response = resolve_target_nodes(<<~QUERY, aggs: aggs)
              target: team_aggregations {
                nodes {
                  sub_aggregations {
                    seasons_nested {
                      nodes {
                        grouped_by { was_shortened }
                        count_detail { approximate_value }
                      }
                    }
                  }
                }
              }
            QUERY

            expect(response).to eq([{
              "sub_aggregations" => {
                "seasons_nested" => {
                  "nodes" => [
                    {"count_detail" => {"approximate_value" => 4}, "grouped_by" => {"was_shortened" => false}},
                    {"count_detail" => {"approximate_value" => 2}, "grouped_by" => {"was_shortened" => true}}
                  ]
                }
              }
            }])
          end

          it "includes a node for the missing value bucket when its count is greater than zero" do
            response_for_0, response_for_3 = [0, 3].map do |missing_bucket_doc_count|
              aggs = {
                "target:seasons_nested" => {
                  "meta" => outer_meta({"buckets_path" => ["seasons_nested.year"]}),
                  "doc_count" => 4,
                  "seasons_nested.year" => {
                    "meta" => inner_terms_meta("seasons_nested.year"),
                    "doc_count_error_upper_bound" => 0,
                    "sum_other_doc_count" => 0,
                    "buckets" => [
                      {
                        "key" => 2020,
                        "doc_count" => 2
                      }
                    ]
                  }
                }.with_missing_value_bucket(missing_bucket_doc_count)
              }

              resolve_target_nodes(<<~QUERY, aggs: aggs)
                target: team_aggregations {
                  nodes {
                    sub_aggregations {
                      seasons_nested {
                        nodes {
                          grouped_by { year }
                          count_detail { approximate_value }
                        }
                      }
                    }
                  }
                }
              QUERY
            end

            expect(response_for_0).to eq([{
              "sub_aggregations" => {
                "seasons_nested" => {
                  "nodes" => [
                    {"count_detail" => {"approximate_value" => 2}, "grouped_by" => {"year" => 2020}}
                  ]
                }
              }
            }])

            expect(response_for_3).to eq([{
              "sub_aggregations" => {
                "seasons_nested" => {
                  "nodes" => [
                    {"count_detail" => {"approximate_value" => 3}, "grouped_by" => {"year" => nil}},
                    {"count_detail" => {"approximate_value" => 2}, "grouped_by" => {"year" => 2020}}
                  ]
                }
              }
            }])
          end

          it "handles a non-empty missing value bucket when a sub-aggregation filter has been applied" do
            aggs = {
              "target:seasons_nested" => {
                "meta" => outer_meta({"buckets_path" => ["seasons_nested:filtered", "seasons_nested.year"]}),
                "doc_count" => 10,
                "seasons_nested:filtered" => {
                  "doc_count" => 5,
                  "seasons_nested.year" => {
                    "meta" => inner_terms_meta("seasons_nested.year"),
                    "doc_count_error_upper_bound" => 0,
                    "sum_other_doc_count" => 0,
                    "buckets" => [
                      {
                        "key" => 2020,
                        "doc_count" => 3
                      }
                    ]
                  }
                }.with_missing_value_bucket(2)
              }
            }

            response = resolve_target_nodes(<<~QUERY, aggs: aggs)
              target: team_aggregations {
                nodes {
                  sub_aggregations {
                    seasons_nested(filter: {year: {not: {equal_to_any_of: [2021]}}}) {
                      nodes {
                        grouped_by { year }
                        count_detail { approximate_value }
                      }
                    }
                  }
                }
              }
            QUERY

            expect(response).to eq([{
              "sub_aggregations" => {
                "seasons_nested" => {
                  "nodes" => [
                    {"count_detail" => {"approximate_value" => 3}, "grouped_by" => {"year" => 2020}},
                    {"count_detail" => {"approximate_value" => 2}, "grouped_by" => {"year" => nil}}
                  ]
                }
              }
            }])
          end

          it "resolves a sub-aggregation grouping on multiple non-date fields when it used multiple terms aggregations" do
            aggs = {
              "target:seasons_nested" => {
                "meta" => outer_meta({"buckets_path" => ["seasons_nested.year"]}),
                "doc_count" => 4,
                "seasons_nested.year" => {
                  "meta" => inner_terms_meta("seasons_nested.year", {"buckets_path" => ["seasons_nested.count"]}),
                  "doc_count_error_upper_bound" => 0,
                  "sum_other_doc_count" => 0,
                  "buckets" => [
                    {
                      "key" => 2020,
                      "doc_count" => 2,
                      "doc_count_error_upper_bound" => 0,
                      "sum_other_doc_count" => 0,
                      "seasons_nested.count" => {
                        "meta" => inner_terms_meta("seasons_nested.count"),
                        "buckets" => [{"key" => 3, "doc_count" => 2}]
                      }
                    }.with_missing_value_bucket(0),
                    {
                      "key" => 2019,
                      "doc_count" => 1,
                      "doc_count_error_upper_bound" => 0,
                      "sum_other_doc_count" => 0,
                      "seasons_nested.count" => {
                        "meta" => inner_terms_meta("seasons_nested.count"),
                        "buckets" => [{"key" => 4, "doc_count" => 1}]
                      }
                    }.with_missing_value_bucket(0),
                    {
                      "key" => 2022,
                      "doc_count" => 1,
                      "doc_count_error_upper_bound" => 0,
                      "sum_other_doc_count" => 0,
                      "seasons_nested.count" => {
                        "meta" => inner_terms_meta("seasons_nested.count"),
                        "buckets" => [{"key" => 1, "doc_count" => 1}]
                      }
                    }.with_missing_value_bucket(0)
                  ]
                }
              }.with_missing_value_bucket(0)
            }

            response = resolve_target_nodes(<<~QUERY, aggs: aggs)
              target: team_aggregations {
                nodes {
                  sub_aggregations {
                    seasons_nested {
                      nodes {
                        grouped_by { year, count }
                        count_detail { approximate_value }
                      }
                    }
                  }
                }
              }
            QUERY

            expect(response).to eq([{
              "sub_aggregations" => {
                "seasons_nested" => {
                  "nodes" => [
                    {"count_detail" => {"approximate_value" => 2}, "grouped_by" => {"year" => 2020, "count" => 3}},
                    {"count_detail" => {"approximate_value" => 1}, "grouped_by" => {"year" => 2019, "count" => 4}},
                    {"count_detail" => {"approximate_value" => 1}, "grouped_by" => {"year" => 2022, "count" => 1}}
                  ]
                }
              }
            }])
          end

          # Note: we used to use multi-terms aggregation but no longer do. Still, it's useful that our resolver is able to
          # handle either kind of response structure. So while it no longer must handle this case, it's useful that it does
          # so and given the test was already written we decided to keep it. If that flexibility ever becomes a maintenance
          # burden, feel free to remove this test.
          it "resolves a sub-aggregation grouping on multiple non-date fields when it used a single multi-terms aggregation" do
            aggs = {
              "target:seasons_nested" => {
                "meta" => outer_meta({"buckets_path" => ["seasons_nested.year_and_count"]}),
                "doc_count" => 4,
                "seasons_nested.year_and_count" => {
                  "meta" => inner_terms_meta(["seasons_nested.year", "seasons_nested.count"]),
                  "doc_count_error_upper_bound" => 0,
                  "sum_other_doc_count" => 0,
                  "buckets" => [
                    {
                      "key" => [2020, 3],
                      "doc_count" => 2
                    },
                    {
                      "key" => [2019, 4],
                      "doc_count" => 1
                    },
                    {
                      "key" => [2022, 1],
                      "doc_count" => 1
                    }
                  ]
                }
              }.with_missing_value_bucket(0)
            }

            response = resolve_target_nodes(<<~QUERY, aggs: aggs)
              target: team_aggregations {
                nodes {
                  sub_aggregations {
                    seasons_nested {
                      nodes {
                        grouped_by { year, count }
                        count_detail { approximate_value }
                      }
                    }
                  }
                }
              }
            QUERY

            expect(response).to eq([{
              "sub_aggregations" => {
                "seasons_nested" => {
                  "nodes" => [
                    {"count_detail" => {"approximate_value" => 2}, "grouped_by" => {"year" => 2020, "count" => 3}},
                    {"count_detail" => {"approximate_value" => 1}, "grouped_by" => {"year" => 2019, "count" => 4}},
                    {"count_detail" => {"approximate_value" => 1}, "grouped_by" => {"year" => 2022, "count" => 1}}
                  ]
                }
              }
            }])
          end

          it "sorts and truncates `terms` buckets on the doc count (descending), with the key (ascending) as a tie-breaker" do
            aggs = {
              "target:seasons_nested" => {
                "meta" => outer_meta({"buckets_path" => ["seasons_nested.year"]}, size: 3),
                "doc_count" => 10,
                "seasons_nested.year" => {
                  "meta" => inner_terms_meta("seasons_nested.year"),
                  "doc_count_error_upper_bound" => 0,
                  "sum_other_doc_count" => 0,
                  "buckets" => [
                    {
                      "key" => 2020,
                      "doc_count" => 2
                    },
                    {
                      "key" => 2019,
                      "doc_count" => 6
                    },
                    {
                      "key" => 2022,
                      "doc_count" => 2
                    },
                    {
                      "key" => 2021,
                      "doc_count" => 2
                    }
                  ]
                }
              }.with_missing_value_bucket(0)
            }

            response = resolve_target_nodes(<<~QUERY, aggs: aggs)
              target: team_aggregations {
                nodes {
                  sub_aggregations {
                    seasons_nested(first: 3) {
                      nodes {
                        grouped_by { year }
                        count_detail { approximate_value }
                      }
                    }
                  }
                }
              }
            QUERY

            expect(response).to eq([{
              "sub_aggregations" => {
                "seasons_nested" => {
                  "nodes" => [
                    {"count_detail" => {"approximate_value" => 6}, "grouped_by" => {"year" => 2019}},
                    {"count_detail" => {"approximate_value" => 2}, "grouped_by" => {"year" => 2020}},
                    {"count_detail" => {"approximate_value" => 2}, "grouped_by" => {"year" => 2021}}
                  ]
                }
              }
            }])
          end

          it "tolerates comparing null/missing key values against string values when sorting the buckets" do
            aggs = {
              "target:seasons_nested" => {
                "meta" => outer_meta({"buckets_path" => ["seasons_nested.note"]}, size: 2),
                "doc_count" => 6,
                "seasons_nested.note" => {
                  "meta" => inner_terms_meta("seasons_nested.note", {"buckets_path" => ["seasons_nested.record.losses"]}),
                  "doc_count_error_upper_bound" => 0,
                  "sum_other_doc_count" => 0,
                  "buckets" => [
                    {
                      "key" => "pandemic",
                      "doc_count" => 2,
                      "doc_count_error_upper_bound" => 0,
                      "seasons_nested.record.losses" => {
                        "meta" => inner_terms_meta("seasons_nested.record.losses"),
                        "doc_count_error_upper_bound" => 0,
                        "sum_other_doc_count" => 0,
                        "buckets" => [
                          {"key" => 12, "doc_count" => 1, "doc_count_error_upper_bound" => 0},
                          {"key" => 22, "doc_count" => 1, "doc_count_error_upper_bound" => 0}
                        ]
                      },
                      "seasons_nested.record.losses:m" => {"doc_count" => 0}
                    },
                    {
                      "key" => "covid",
                      "doc_count" => 1,
                      "doc_count_error_upper_bound" => 0,
                      "seasons_nested.record.losses" => {
                        "meta" => inner_terms_meta("seasons_nested.record.losses"),
                        "doc_count_error_upper_bound" => 0,
                        "sum_other_doc_count" => 0,
                        "buckets" => [
                          {"key" => 22, "doc_count" => 1, "doc_count_error_upper_bound" => 0}
                        ]
                      },
                      "seasons_nested.record.losses:m" => {"doc_count" => 0}
                    }
                  ]
                },
                "seasons_nested.note:m" => {
                  "meta" => inner_terms_meta("seasons_nested.note", {"buckets_path" => ["seasons_nested.record.losses"]}),
                  "doc_count" => 3,
                  "seasons_nested.record.losses" => {
                    "meta" => inner_terms_meta("seasons_nested.record.losses"),
                    "doc_count_error_upper_bound" => 0,
                    "sum_other_doc_count" => 0,
                    "buckets" => [
                      {"key" => 15, "doc_count" => 1, "doc_count_error_upper_bound" => 0},
                      {"key" => 22, "doc_count" => 1, "doc_count_error_upper_bound" => 0}
                    ]
                  },
                  "seasons_nested.record.losses:m" => {"doc_count" => 1}
                }
              }
            }

            response = resolve_target_nodes(<<~QUERY, aggs: aggs)
              target: team_aggregations {
                nodes {
                  sub_aggregations {
                    seasons_nested(first: 2) {
                      nodes {
                        grouped_by { note, record { losses } }
                        count_detail { approximate_value }
                      }
                    }
                  }
                }
              }
            QUERY

            expect(response).to eq([{
              "sub_aggregations" => {
                "seasons_nested" => {
                  "nodes" => [
                    {"count_detail" => {"approximate_value" => 1}, "grouped_by" => {"note" => nil, "record" => {"losses" => nil}}},
                    {"count_detail" => {"approximate_value" => 1}, "grouped_by" => {"note" => nil, "record" => {"losses" => 15}}}
                  ]
                }
              }
            }])
          end

          it "sorts and truncates `terms` buckets on the doc count (descending), with the key values (ascending) as a tie-breaker when a multiple terms aggregations were used" do
            aggs = {
              "target:seasons_nested" => {
                "meta" => outer_meta({"buckets_path" => ["seasons_nested.year"]}, size: 3),
                "doc_count" => 21,
                "seasons_nested.year" => {
                  "meta" => inner_terms_meta("seasons_nested.year", {"buckets_path" => ["seasons_nested.count"]}),
                  "doc_count_error_upper_bound" => 0,
                  "sum_other_doc_count" => 0,
                  "buckets" => [
                    {
                      "key" => 2022,
                      "doc_count" => 4,
                      "doc_count_error_upper_bound" => 0,
                      "sum_other_doc_count" => 0,
                      "seasons_nested.count" => {
                        "meta" => inner_terms_meta("seasons_nested.count"),
                        "buckets" => [
                          {"key" => 1, "doc_count" => 4}
                        ]
                      }
                    }.with_missing_value_bucket(0),
                    {
                      "key" => 2020,
                      "doc_count" => 8,
                      "doc_count_error_upper_bound" => 0,
                      "sum_other_doc_count" => 0,
                      "seasons_nested.count" => {
                        "meta" => inner_terms_meta("seasons_nested.count"),
                        "buckets" => [
                          {"key" => 1, "doc_count" => 4},
                          {"key" => 3, "doc_count" => 4}
                        ]
                      }
                    }.with_missing_value_bucket(0),
                    {
                      "key" => 2019,
                      "doc_count" => 9,
                      "doc_count_error_upper_bound" => 0,
                      "sum_other_doc_count" => 0,
                      "seasons_nested.count" => {
                        "meta" => inner_terms_meta("seasons_nested.count"),
                        "buckets" => [
                          {"key" => 4, "doc_count" => 9}
                        ]
                      }
                    }.with_missing_value_bucket(0)
                  ]
                }
              }.with_missing_value_bucket(0)
            }

            response = resolve_target_nodes(<<~QUERY, aggs: aggs)
              target: team_aggregations {
                nodes {
                  sub_aggregations {
                    seasons_nested(first: 3) {
                      nodes {
                        grouped_by { year, count }
                        count_detail { approximate_value }
                      }
                    }
                  }
                }
              }
            QUERY

            expect(response).to eq([{
              "sub_aggregations" => {
                "seasons_nested" => {
                  "nodes" => [
                    {"count_detail" => {"approximate_value" => 9}, "grouped_by" => {"year" => 2019, "count" => 4}},
                    {"count_detail" => {"approximate_value" => 4}, "grouped_by" => {"year" => 2020, "count" => 1}},
                    {"count_detail" => {"approximate_value" => 4}, "grouped_by" => {"year" => 2020, "count" => 3}}
                  ]
                }
              }
            }])
          end

          # Note: we used to use multi-terms aggregation but no longer do. Still, it's useful that our resolver is able to
          # handle either kind of response structure. So while it no longer must handle this case, it's useful that it does
          # so and given the test was already written we decided to keep it. If that flexibility ever becomes a maintenance
          # burden, feel free to remove this test.
          it "sorts and truncates `terms` buckets on the doc count (descending), with the key values (ascending) as a tie-breaker when a single multi-terms aggregation was used" do
            aggs = {
              "target:seasons_nested" => {
                "meta" => outer_meta({"buckets_path" => ["seasons_nested.year_and_count"]}, size: 3),
                "doc_count" => 21,
                "seasons_nested.year_and_count" => {
                  "meta" => inner_terms_meta(["seasons_nested.year", "seasons_nested.count"]),
                  "doc_count_error_upper_bound" => 0,
                  "sum_other_doc_count" => 0,
                  "buckets" => [
                    {
                      "key" => [2022, 1],
                      "doc_count" => 4
                    },
                    {
                      "key" => [2020, 1],
                      "doc_count" => 4
                    },
                    {
                      "key" => [2019, 4],
                      "doc_count" => 9
                    },
                    {
                      "key" => [2020, 3],
                      "doc_count" => 4
                    }
                  ]
                }
              }.with_missing_value_bucket(0)
            }

            response = resolve_target_nodes(<<~QUERY, aggs: aggs)
              target: team_aggregations {
                nodes {
                  sub_aggregations {
                    seasons_nested(first: 3) {
                      nodes {
                        grouped_by { year, count }
                        count_detail { approximate_value }
                      }
                    }
                  }
                }
              }
            QUERY

            expect(response).to eq([{
              "sub_aggregations" => {
                "seasons_nested" => {
                  "nodes" => [
                    {"count_detail" => {"approximate_value" => 9}, "grouped_by" => {"year" => 2019, "count" => 4}},
                    {"count_detail" => {"approximate_value" => 4}, "grouped_by" => {"year" => 2020, "count" => 1}},
                    {"count_detail" => {"approximate_value" => 4}, "grouped_by" => {"year" => 2020, "count" => 3}}
                  ]
                }
              }
            }])
          end

          it "resolves a sub-aggregation grouping on a single date field" do
            aggs = {
              "target:seasons_nested" => {
                "meta" => outer_meta({"buckets_path" => ["seasons_nested.started_at.as_date_time"]}),
                "doc_count" => 6,
                "seasons_nested.started_at.as_date_time" => {
                  "meta" => inner_date_meta("seasons_nested.started_at.as_date_time"),
                  "doc_count_error_upper_bound" => 0,
                  "sum_other_doc_count" => 0,
                  "buckets" => [
                    {
                      "key_as_string" => "2019-01-01T00:00:00.000Z",
                      "key" => 1546300800000,
                      "doc_count" => 3
                    },
                    {
                      "key_as_string" => "2020-01-01T00:00:00.000Z",
                      "key" => 1577836800000,
                      "doc_count" => 2
                    },
                    {
                      "key_as_string" => "2022-01-01T00:00:00.000Z",
                      "key" => 1640995200000,
                      "doc_count" => 1
                    }
                  ]
                }
              }.with_missing_value_bucket(0)
            }

            response = resolve_target_nodes(<<~QUERY, aggs: aggs)
              target: team_aggregations {
                nodes {
                  sub_aggregations {
                    seasons_nested {
                      nodes {
                        grouped_by { started_at { as_date_time(truncation_unit: YEAR) }}
                        count_detail { approximate_value }
                      }
                    }
                  }
                }
              }
            QUERY

            expect(response).to eq([{
              "sub_aggregations" => {
                "seasons_nested" => {
                  "nodes" => [
                    {"count_detail" => {"approximate_value" => 3}, "grouped_by" => {"started_at" => {"as_date_time" => "2019-01-01T00:00:00.000Z"}}},
                    {"count_detail" => {"approximate_value" => 2}, "grouped_by" => {"started_at" => {"as_date_time" => "2020-01-01T00:00:00.000Z"}}},
                    {"count_detail" => {"approximate_value" => 1}, "grouped_by" => {"started_at" => {"as_date_time" => "2022-01-01T00:00:00.000Z"}}}
                  ]
                }
              }
            }])
          end

          it "resolves a sub-aggregation grouping on a non-date field and multiple date fields (requiring a 3-level datastore response structure)" do
            # This is the response structure we get when we put a `terms` aggregation outside a `date_histogram` aggregation.
            terms_outside_date_aggs = {
              "target:seasons_nested" => {
                "meta" => outer_meta({"buckets_path" => ["seasons_nested.year"]}),
                "doc_count" => 18,
                "seasons_nested.year" => {
                  "meta" => inner_terms_meta("seasons_nested.year", {"buckets_path" => ["seasons_nested.started_at.as_date_time"]}),
                  "doc_count_error_upper_bound" => 0,
                  "sum_other_doc_count" => 0,
                  "buckets" => [
                    {
                      "key" => 2020,
                      "doc_count" => 11,
                      "seasons_nested.started_at.as_date_time" => {
                        "meta" => inner_date_meta("seasons_nested.started_at.as_date_time", {"buckets_path" => ["seasons_nested.won_games_at"]}),
                        "buckets" => [
                          {
                            "key_as_string" => "2020-01-01T00:00:00.000Z",
                            "key" => 1577836800000,
                            "doc_count" => 11,
                            "seasons_nested.won_games_at" => {
                              "meta" => inner_date_meta("seasons_nested.won_game_at.as_date_time"),
                              "buckets" => [
                                {
                                  "key_as_string" => "2020-01-01T00:00:00.000Z",
                                  "key" => 1577836800000,
                                  "doc_count" => 6
                                },
                                {
                                  "key_as_string" => "2019-01-01T00:00:00.000Z",
                                  "key" => 1546300800000,
                                  "doc_count" => 5
                                }
                              ]
                            }
                          }.with_missing_value_bucket(0)
                        ]
                      }
                    }.with_missing_value_bucket(0),
                    {
                      "key" => 2019,
                      "doc_count" => 7,
                      "seasons_nested.started_at.as_date_time" => {
                        "meta" => inner_date_meta("seasons_nested.started_at.as_date_time", {"buckets_path" => ["seasons_nested.won_games_at"]}),
                        "buckets" => [
                          {
                            "key_as_string" => "2019-01-01T00:00:00.000Z",
                            "key" => 1546300800000,
                            "doc_count" => 4,
                            "seasons_nested.won_games_at" => {
                              "meta" => inner_date_meta("seasons_nested.won_game_at.as_date_time"),
                              "buckets" => [
                                {
                                  "key_as_string" => "2019-01-01T00:00:00.000Z",
                                  "key" => 1546300800000,
                                  "doc_count" => 4
                                }
                              ]
                            }
                          }.with_missing_value_bucket(0),
                          {
                            "key_as_string" => "2021-01-01T00:00:00.000Z",
                            "key" => 1609459200000,
                            "doc_count" => 3,
                            "seasons_nested.won_games_at" => {
                              "meta" => inner_date_meta("seasons_nested.won_game_at.as_date_time"),
                              "buckets" => [
                                {
                                  "key_as_string" => "2021-01-01T00:00:00.000Z",
                                  "key" => 1609459200000,
                                  "doc_count" => 3
                                }
                              ]
                            }
                          }.with_missing_value_bucket(0)
                        ]
                      }
                    }.with_missing_value_bucket(0)
                  ]
                }
              }.with_missing_value_bucket(0)
            }

            # This is the response structure we get when we put a `terms` aggregation inside a `date_histogram` aggregation.
            terms_inside_date_aggs = {
              "target:seasons_nested" => {
                "meta" => outer_meta({"buckets_path" => ["seasons_nested.started_at.as_date_time"]}),
                "doc_count" => 18,
                "seasons_nested.started_at.as_date_time" => {
                  "meta" => inner_date_meta("seasons_nested.started_at.as_date_time", {"buckets_path" => ["seasons_nested.won_games_at"]}),
                  "buckets" => [
                    {
                      "key_as_string" => "2019-01-01T00:00:00.000Z",
                      "key" => 1546300800000,
                      "doc_count" => 4,
                      "seasons_nested.won_games_at" => {
                        "meta" => inner_date_meta("seasons_nested.won_game_at.as_date_time", {"buckets_path" => ["seasons_nested.year"]}),
                        "buckets" => [
                          {
                            "key_as_string" => "2019-01-01T00:00:00.000Z",
                            "key" => 1546300800000,
                            "doc_count" => 4,
                            "seasons_nested.year" => {
                              "meta" => inner_terms_meta("seasons_nested.year"),
                              "doc_count_error_upper_bound" => 0,
                              "sum_other_doc_count" => 0,
                              "buckets" => [
                                {
                                  "key" => 2019,
                                  "doc_count" => 4
                                }
                              ]
                            }
                          }.with_missing_value_bucket(0)
                        ]
                      }
                    }.with_missing_value_bucket(0),
                    {
                      "key_as_string" => "2020-01-01T00:00:00.000Z",
                      "key" => 1577836800000,
                      "doc_count" => 2,
                      "seasons_nested.won_games_at" => {
                        "meta" => inner_date_meta("seasons_nested.won_game_at.as_date_time", {"buckets_path" => ["seasons_nested.year"]}),
                        "buckets" => [
                          {
                            "key_as_string" => "2019-01-01T00:00:00.000Z",
                            "key" => 1546300800000,
                            "doc_count" => 5,
                            "seasons_nested.year" => {
                              "meta" => inner_terms_meta("seasons_nested.year"),
                              "doc_count_error_upper_bound" => 0,
                              "sum_other_doc_count" => 0,
                              "buckets" => [
                                {
                                  "key" => 2020,
                                  "doc_count" => 5
                                }
                              ]
                            }
                          }.with_missing_value_bucket(0),
                          {
                            "key_as_string" => "2020-01-01T00:00:00.000Z",
                            "key" => 1577836800000,
                            "doc_count" => 6,
                            "seasons_nested.year" => {
                              "meta" => inner_terms_meta("seasons_nested.year"),
                              "doc_count_error_upper_bound" => 0,
                              "sum_other_doc_count" => 0,
                              "buckets" => [
                                {
                                  "key" => 2020,
                                  "doc_count" => 6
                                }
                              ]
                            }
                          }.with_missing_value_bucket(0)
                        ]
                      }
                    }.with_missing_value_bucket(0),
                    {
                      "key_as_string" => "2021-01-01T00:00:00.000Z",
                      "key" => 1609459200000,
                      "doc_count" => 1,
                      "seasons_nested.won_games_at" => {
                        "meta" => inner_date_meta("seasons_nested.won_game_at.as_date_time", {"buckets_path" => ["seasons_nested.year"]}),
                        "buckets" => [
                          {
                            "key_as_string" => "2021-01-01T00:00:00.000Z",
                            "key" => 1609459200000,
                            "doc_count" => 3,
                            "seasons_nested.year" => {
                              "meta" => inner_terms_meta("seasons_nested.year"),
                              "doc_count_error_upper_bound" => 0,
                              "sum_other_doc_count" => 0,
                              "buckets" => [
                                {
                                  "key" => 2019,
                                  "doc_count" => 3
                                }
                              ]
                            }
                          }.with_missing_value_bucket(0)
                        ]
                      }
                    }.with_missing_value_bucket(0)
                  ]
                }
              }.with_missing_value_bucket(0)
            }

            terms_inside_date_response, terms_outside_date_response = [terms_inside_date_aggs, terms_outside_date_aggs].map do |aggs|
              resolve_target_nodes(<<~QUERY, aggs: aggs)
                target: team_aggregations {
                  nodes {
                    sub_aggregations {
                      seasons_nested {
                        nodes {
                          grouped_by {
                            started_at { as_date_time(truncation_unit: YEAR) }
                            year
                            won_game_at { as_date_time(truncation_unit: YEAR) }
                          }
                          count_detail { approximate_value }
                        }
                      }
                    }
                  }
                }
              QUERY
            end

            # Our resolver should be able to handle either nesting ordering. On 2023-12-05, we swapped the ordering
            # (from `terms { date { ... } }` to `date { terms { ... } }`). We want our resolver to handle either
            # order, so here we test both, expecting the same response in either case.
            expect(terms_inside_date_response).to eq(terms_outside_date_response)
            expect(terms_inside_date_response).to eq([{
              "sub_aggregations" => {
                "seasons_nested" => {
                  "nodes" => [
                    {
                      "count_detail" => {"approximate_value" => 6},
                      "grouped_by" => {
                        "year" => 2020,
                        "started_at" => {"as_date_time" => "2020-01-01T00:00:00.000Z"},
                        "won_game_at" => {"as_date_time" => "2020-01-01T00:00:00.000Z"}
                      }
                    },
                    {
                      "count_detail" => {"approximate_value" => 5},
                      "grouped_by" => {
                        "year" => 2020,
                        "started_at" => {"as_date_time" => "2020-01-01T00:00:00.000Z"},
                        "won_game_at" => {"as_date_time" => "2019-01-01T00:00:00.000Z"}
                      }
                    },
                    {
                      "count_detail" => {"approximate_value" => 4},
                      "grouped_by" => {
                        "year" => 2019,
                        "started_at" => {"as_date_time" => "2019-01-01T00:00:00.000Z"},
                        "won_game_at" => {"as_date_time" => "2019-01-01T00:00:00.000Z"}
                      }
                    },
                    {
                      "count_detail" => {"approximate_value" => 3},
                      "grouped_by" => {
                        "year" => 2019,
                        "started_at" => {"as_date_time" => "2021-01-01T00:00:00.000Z"},
                        "won_game_at" => {"as_date_time" => "2021-01-01T00:00:00.000Z"}
                      }
                    }
                  ]
                }
              }
            }])
          end

          it "sorts and truncates single-layer `date_histogram` buckets on the doc count (descending), with the key values (ascending) as a tie-breaker" do
            aggs = {
              "target:seasons_nested" => {
                "meta" => outer_meta({"buckets_path" => ["seasons_nested.started_at.as_date_time"]}, size: 3),
                "doc_count" => 18,
                "seasons_nested.started_at.as_date_time" => {
                  "meta" => inner_date_meta("seasons_nested.started_at.as_date_time"),
                  "doc_count_error_upper_bound" => 0,
                  "sum_other_doc_count" => 0,
                  "buckets" => [
                    {
                      "key_as_string" => "2019-01-01T00:00:00.000Z",
                      "key" => 1546300800000,
                      "doc_count" => 3
                    },
                    {
                      "key_as_string" => "2022-01-01T00:00:00.000Z",
                      "key" => 1640995200000,
                      "doc_count" => 3
                    },
                    {
                      "key_as_string" => "2021-01-01T00:00:00.000Z",
                      "key" => 1609459200000,
                      "doc_count" => 9
                    },
                    {
                      "key_as_string" => "2020-01-01T00:00:00.000Z",
                      "key" => 1577836800000,
                      "doc_count" => 3
                    }
                  ]
                }
              }.with_missing_value_bucket(0)
            }

            response = resolve_target_nodes(<<~QUERY, aggs: aggs)
              target: team_aggregations {
                nodes {
                  sub_aggregations {
                    seasons_nested(first: 3) {
                      nodes {
                        grouped_by { started_at { as_date_time(truncation_unit: YEAR) }}
                        count_detail { approximate_value }
                      }
                    }
                  }
                }
              }
            QUERY

            expect(response).to eq([{
              "sub_aggregations" => {
                "seasons_nested" => {
                  "nodes" => [
                    {"count_detail" => {"approximate_value" => 9}, "grouped_by" => {"started_at" => {"as_date_time" => "2021-01-01T00:00:00.000Z"}}},
                    {"count_detail" => {"approximate_value" => 3}, "grouped_by" => {"started_at" => {"as_date_time" => "2019-01-01T00:00:00.000Z"}}},
                    {"count_detail" => {"approximate_value" => 3}, "grouped_by" => {"started_at" => {"as_date_time" => "2020-01-01T00:00:00.000Z"}}}
                  ]
                }
              }
            }])
          end

          it "sorts and truncates a complex multi-layer `date_histogram` + `term` buckets on the doc count (descending), with the key values (ascending) as a tie-breaker" do
            aggs = {
              "target:seasons_nested" => {
                "meta" => outer_meta({"buckets_path" => ["seasons_nested.year"]}, size: 5),
                "doc_count" => 18,
                "seasons_nested.year" => {
                  "meta" => inner_terms_meta("seasons_nested.year", {"buckets_path" => ["seasons_nested.started_at.as_date_time"]}),
                  "doc_count_error_upper_bound" => 0,
                  "sum_other_doc_count" => 0,
                  "buckets" => [
                    {
                      "key" => 2020,
                      "doc_count" => 18,
                      "seasons_nested.started_at.as_date_time" => {
                        "meta" => inner_date_meta("seasons_nested.started_at.as_date_time", {"buckets_path" => ["seasons_nested.won_games_at"]}),
                        "buckets" => [
                          {
                            "key_as_string" => "2020-01-01T00:00:00.000Z",
                            "key" => 1577836800000,
                            "doc_count" => 18,
                            "seasons_nested.won_games_at" => {
                              "meta" => inner_date_meta("seasons_nested.won_game_at.as_date_time"),
                              "buckets" => [
                                {
                                  "key_as_string" => "2019-01-01T00:00:00.000Z",
                                  "key" => 1546300800000,
                                  "doc_count" => 3
                                },
                                {
                                  "key_as_string" => "2022-01-01T00:00:00.000Z",
                                  "key" => 1640995200000,
                                  "doc_count" => 3
                                },
                                {
                                  "key_as_string" => "2021-01-01T00:00:00.000Z",
                                  "key" => 1609459200000,
                                  "doc_count" => 9
                                },
                                {
                                  "key_as_string" => "2020-01-01T00:00:00.000Z",
                                  "key" => 1577836800000,
                                  "doc_count" => 3
                                }
                              ]
                            }
                          }.with_missing_value_bucket(0)
                        ]
                      }
                    }.with_missing_value_bucket(0),
                    {
                      "key" => 2019,
                      "doc_count" => 11,
                      "seasons_nested.started_at.as_date_time" => {
                        "meta" => inner_date_meta("seasons_nested.started_at.as_date_time", {"buckets_path" => ["seasons_nested.won_games_at"]}),
                        "buckets" => [
                          {
                            "key_as_string" => "2019-01-01T00:00:00.000Z",
                            "key" => 1546300800000,
                            "doc_count" => 11,
                            "seasons_nested.won_games_at" => {
                              "meta" => inner_date_meta("seasons_nested.won_game_at.as_date_time"),
                              "buckets" => [
                                {
                                  "key_as_string" => "2019-01-01T00:00:00.000Z",
                                  "key" => 1546300800000,
                                  "doc_count" => 11
                                }
                              ]
                            }
                          }.with_missing_value_bucket(0),
                          {
                            "key_as_string" => "2021-01-01T00:00:00.000Z",
                            "key" => 1609459200000,
                            "doc_count" => 2,
                            "seasons_nested.won_games_at" => {
                              "meta" => inner_date_meta("seasons_nested.won_game_at.as_date_time"),
                              "buckets" => [
                                {
                                  "key_as_string" => "2021-01-01T00:00:00.000Z",
                                  "key" => 1609459200000,
                                  "doc_count" => 2
                                }
                              ]
                            }
                          }.with_missing_value_bucket(0)
                        ]
                      }
                    }.with_missing_value_bucket(0)
                  ]
                }
              }.with_missing_value_bucket(0)
            }

            response = resolve_target_nodes(<<~QUERY, aggs: aggs)
              target: team_aggregations {
                nodes {
                  sub_aggregations {
                    seasons_nested(first: 5) {
                      nodes {
                        grouped_by {
                          started_at { as_date_time(truncation_unit: YEAR) }
                          year
                          won_game_at { as_date_time(truncation_unit: YEAR) }
                        }
                        count_detail { approximate_value }
                      }
                    }
                  }
                }
              }
            QUERY

            expect(response).to eq([{
              "sub_aggregations" => {
                "seasons_nested" => {
                  "nodes" => [
                    {
                      "count_detail" => {"approximate_value" => 11},
                      "grouped_by" => {
                        "year" => 2019,
                        "started_at" => {"as_date_time" => "2019-01-01T00:00:00.000Z"},
                        "won_game_at" => {"as_date_time" => "2019-01-01T00:00:00.000Z"}
                      }
                    },
                    {
                      "count_detail" => {"approximate_value" => 9},
                      "grouped_by" => {
                        "year" => 2020,
                        "started_at" => {"as_date_time" => "2020-01-01T00:00:00.000Z"},
                        "won_game_at" => {"as_date_time" => "2021-01-01T00:00:00.000Z"}
                      }
                    },
                    {
                      "count_detail" => {"approximate_value" => 3},
                      "grouped_by" => {
                        "year" => 2020,
                        "started_at" => {"as_date_time" => "2020-01-01T00:00:00.000Z"},
                        "won_game_at" => {"as_date_time" => "2019-01-01T00:00:00.000Z"}
                      }
                    },
                    {
                      "count_detail" => {"approximate_value" => 3},
                      "grouped_by" => {
                        "year" => 2020,
                        "started_at" => {"as_date_time" => "2020-01-01T00:00:00.000Z"},
                        "won_game_at" => {"as_date_time" => "2020-01-01T00:00:00.000Z"}
                      }
                    },
                    {
                      "count_detail" => {"approximate_value" => 3},
                      "grouped_by" => {
                        "year" => 2020,
                        "started_at" => {"as_date_time" => "2020-01-01T00:00:00.000Z"},
                        "won_game_at" => {"as_date_time" => "2022-01-01T00:00:00.000Z"}
                      }
                    }
                  ]
                }
              }
            }])
          end
        end
      end
    end
  end
end
