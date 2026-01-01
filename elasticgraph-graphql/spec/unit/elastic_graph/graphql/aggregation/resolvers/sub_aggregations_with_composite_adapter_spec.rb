# Copyright 2024 - 2026 Block, Inc.
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
      RSpec.describe Resolvers, "for sub-aggregations, when the `CompositeGroupingAdapter` adapter is used" do
        include_context "aggregation resolver support"
        include_context "sub-aggregation support", Aggregation::CompositeGroupingAdapter
        it_behaves_like "ungrouped sub-aggregations"

        context "with grouping" do
          it "resolves a sub-aggregation grouping on multiple fields" do
            aggs = {
              "target:seasons_nested" => {
                "meta" => outer_meta({"buckets_path" => ["seasons_nested"]}),
                "doc_count" => 9,
                "seasons_nested" => {
                  "after_key" => {"seasons_nested.year" => 2022, "seasons_nested.note" => nil},
                  "buckets" => [
                    {
                      "key" => {"seasons_nested.year" => 2019, "seasons_nested.note" => "old rules"},
                      "doc_count" => 3
                    },
                    {
                      "key" => {"seasons_nested.year" => 2020, "seasons_nested.note" => "covid"},
                      "doc_count" => 4
                    },
                    {
                      "key" => {"seasons_nested.year" => 2020, "seasons_nested.note" => "pandemic"},
                      "doc_count" => 2
                    }
                  ]
                }
              }
            }

            response = resolve_target_nodes(<<~QUERY, aggs: aggs)
              target: team_aggregations {
                nodes {
                  sub_aggregations {
                    seasons_nested {
                      nodes {
                        grouped_by { year, note }
                        count_detail { approximate_value }
                      }
                    }
                  }
                }
              }
            QUERY

            expect(response).to eq [
              {
                "sub_aggregations" => {
                  "seasons_nested" => {
                    "nodes" => [
                      {
                        "grouped_by" => {"year" => 2019, "note" => "old rules"},
                        "count_detail" => {"approximate_value" => 3}
                      },
                      {
                        "grouped_by" => {"year" => 2020, "note" => "covid"},
                        "count_detail" => {"approximate_value" => 4}
                      },
                      {
                        "grouped_by" => {"year" => 2020, "note" => "pandemic"},
                        "count_detail" => {"approximate_value" => 2}
                      }
                    ]
                  }
                }
              }
            ]
          end

          it "resolves all `count_detail` fields with the same value (since we always have the exact count!)" do
            aggs = {
              "target:seasons_nested" => {
                "meta" => outer_meta({"buckets_path" => ["seasons_nested"]}),
                "doc_count" => 7,
                "seasons_nested" => {
                  "after_key" => {"seasons_nested.year" => 2022, "seasons_nested.note" => nil},
                  "buckets" => [
                    {
                      "key" => {"seasons_nested.year" => 2019, "seasons_nested.note" => "old rules"},
                      "doc_count" => 3
                    },
                    {
                      "key" => {"seasons_nested.year" => 2020, "seasons_nested.note" => "covid"},
                      "doc_count" => 4
                    }
                  ]
                }
              }
            }

            response = resolve_target_nodes(<<~QUERY, aggs: aggs)
              target: team_aggregations {
                nodes {
                  sub_aggregations {
                    seasons_nested {
                      nodes {
                        grouped_by { year, note }
                        count_detail { approximate_value, exact_value, upper_bound }
                      }
                    }
                  }
                }
              }
            QUERY

            expect(response).to eq [
              {
                "sub_aggregations" => {
                  "seasons_nested" => {
                    "nodes" => [
                      {
                        "grouped_by" => {"year" => 2019, "note" => "old rules"},
                        "count_detail" => {"approximate_value" => 3, "exact_value" => 3, "upper_bound" => 3}
                      },
                      {
                        "grouped_by" => {"year" => 2020, "note" => "covid"},
                        "count_detail" => {"approximate_value" => 4, "exact_value" => 4, "upper_bound" => 4}
                      }
                    ]
                  }
                }
              }
            ]
          end

          it "resolves all `page_info` fields" do
            query_with_first = lambda do |first|
              aggs = {
                "target:seasons_nested" => {
                  "meta" => outer_meta({"buckets_path" => ["seasons_nested"]}, size: first),
                  "doc_count" => 7,
                  "seasons_nested" => {
                    "after_key" => {"seasons_nested.year" => 2022, "seasons_nested.note" => nil},
                    "buckets" => [
                      {
                        "key" => {"seasons_nested.year" => 2019, "seasons_nested.note" => "old rules"},
                        "doc_count" => 3
                      },
                      {
                        "key" => {"seasons_nested.year" => 2020, "seasons_nested.note" => "covid"},
                        "doc_count" => 4
                      }
                    ]
                  }
                }
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
                          grouped_by { year, note }
                        }
                      }
                    }
                  }
                }
              QUERY
            end

            expect(query_with_first.call(2)).to match [
              {
                "sub_aggregations" => {
                  "seasons_nested" => {
                    "page_info" => an_object_matching({
                      "has_next_page" => false, # false since we only got 2 buckets (the requested amount)
                      "has_previous_page" => false,
                      "start_cursor" => /\w+/,
                      "end_cursor" => /\w+/
                    }),
                    "nodes" => [
                      {"grouped_by" => {"year" => 2019, "note" => "old rules"}},
                      {"grouped_by" => {"year" => 2020, "note" => "covid"}}
                    ]
                  }
                }
              }
            ]

            expect(query_with_first.call(1)).to match [
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
                      {"grouped_by" => {"year" => 2019, "note" => "old rules"}}
                    ]
                  }
                }
              }
            ]
          end

          it "handles filtering" do
            aggs = {
              "target:seasons_nested" => {
                "meta" => outer_meta({"buckets_path" => ["seasons_nested:filtered", "seasons_nested"]}),
                "doc_count" => 9,
                "seasons_nested:filtered" => {
                  "doc_count" => 3,
                  "seasons_nested" => {
                    "after_key" => {"seasons_nested.year" => 2020},
                    "buckets" => [
                      {
                        "key" => {"seasons_nested.year" => 2019},
                        "doc_count" => 1
                      },
                      {
                        "key" => {"seasons_nested.year" => 2020},
                        "doc_count" => 2
                      }
                    ]
                  }
                }
              }
            }

            response = resolve_target_nodes(<<~QUERY, aggs: aggs)
              target: team_aggregations {
                nodes {
                  sub_aggregations {
                    seasons_nested(filter: {year: {lt: 2021}}) {
                      nodes {
                        grouped_by { year }
                        count_detail { approximate_value }
                      }
                    }
                  }
                }
              }
            QUERY

            expect(response).to eq [
              {
                "sub_aggregations" => {
                  "seasons_nested" => {
                    "nodes" => [
                      {
                        "grouped_by" => {"year" => 2019},
                        "count_detail" => {"approximate_value" => 1}
                      },
                      {
                        "grouped_by" => {"year" => 2020},
                        "count_detail" => {"approximate_value" => 2}
                      }
                    ]
                  }
                }
              }
            ]
          end
        end
      end
    end
  end
end
