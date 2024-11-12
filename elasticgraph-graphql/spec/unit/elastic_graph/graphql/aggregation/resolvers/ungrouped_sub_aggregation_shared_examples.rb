# Copyright 2024 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  class GraphQL
    module Aggregation
      # The CompositeAggregationAdapter and NonCompositeAggregationAdapter deal with the same requests and responses
      # when no groupign is involved, so we can use shared examples for those cases.
      RSpec.shared_examples_for "ungrouped sub-aggregations" do
        it "resolves ungrouped sub-aggregations with just a count_detail under an ungrouped aggregation" do
          aggs = {
            "target:seasons_nested" => {"doc_count" => 423, "meta" => outer_meta},
            "target:current_players_nested" => {"doc_count" => 201, "meta" => outer_meta}
          }

          response = resolve_target_nodes(<<~QUERY, aggs: aggs)
            target: team_aggregations {
              nodes {
                sub_aggregations {
                  seasons_nested {
                    nodes {
                      count_detail { approximate_value }
                    }
                  }

                  current_players_nested {
                    nodes {
                      count_detail { approximate_value }
                    }
                  }
                }
              }
            }
          QUERY

          expect(response).to eq [{
            "sub_aggregations" => {
              "seasons_nested" => {"nodes" => [{
                "count_detail" => {"approximate_value" => 423}
              }]},
              "current_players_nested" => {"nodes" => [{
                "count_detail" => {"approximate_value" => 201}
              }]}
            }
          }]
        end

        it "resolves an aliased sub-aggregation" do
          aggs = {
            "target:inner_target" => {"doc_count" => 423, "meta" => outer_meta}
          }

          response = resolve_target_nodes(<<~QUERY, aggs: aggs)
            target: team_aggregations {
              nodes {
                sub_aggregations {
                  inner_target: seasons_nested {
                    nodes {
                      count_detail { approximate_value }
                    }
                  }
                }
              }
            }
          QUERY

          expect(response).to eq [{
            "sub_aggregations" => {
              "inner_target" => {"nodes" => [{
                "count_detail" => {"approximate_value" => 423}
              }]}
            }
          }]
        end

        it "resolves an ungrouped sub-aggregation with just a count_detail under a grouped aggregation" do
          target_buckets = [
            {
              "key" => {"current_name" => "Yankees"},
              "doc_count" => 1,
              "target:seasons_nested" => {"doc_count" => 3, "meta" => outer_meta}
            },
            {
              "key" => {"current_name" => "Dodgers"},
              "doc_count" => 1,
              "target:seasons_nested" => {"doc_count" => 9, "meta" => outer_meta}
            }
          ]

          response = resolve_target_nodes(<<~QUERY, target_buckets: target_buckets)
            target: team_aggregations {
              nodes {
                grouped_by { current_name }
                sub_aggregations {
                  seasons_nested {
                    nodes {
                      count_detail {
                        approximate_value
                      }
                    }
                  }
                }
              }
            }
          QUERY

          expect(response).to eq [
            {
              "grouped_by" => {"current_name" => "Yankees"},
              "sub_aggregations" => {"seasons_nested" => {"nodes" => [{
                "count_detail" => {"approximate_value" => 3}
              }]}}
            },
            {
              "grouped_by" => {"current_name" => "Dodgers"},
              "sub_aggregations" => {"seasons_nested" => {"nodes" => [{
                "count_detail" => {"approximate_value" => 9}
              }]}}
            }
          ]
        end

        it "resolves a sub-aggregation embedded under an extra object layer and respects alternate `name_in_index`" do
          aggs = {
            "target:nested_fields.seasons" => {"doc_count" => 423, "meta" => outer_meta}
          }

          response = resolve_target_nodes(<<~QUERY, aggs: aggs)
            target: team_aggregations {
              nodes {
                sub_aggregations {
                  nested_fields { # called the_nested_fields in the index
                    seasons { # called the_seasons in the index
                      nodes {
                        count_detail { approximate_value }
                      }
                    }
                  }
                }
              }
            }
          QUERY

          expect(response).to eq [{
            "sub_aggregations" => {
              "nested_fields" => {
                "seasons" => {"nodes" => [{
                  "count_detail" => {"approximate_value" => 423}
                }]}
              }
            }
          }]
        end

        it "resolves sub-aggregations of sub-aggregations of sub-aggregations" do
          aggs = {
            "target:seasons_nested" => {
              "doc_count" => 4,
              "meta" => outer_meta,
              "target:seasons_nested:seasons_nested.players_nested" => {
                "doc_count" => 25,
                "meta" => outer_meta,
                "target:seasons_nested:players_nested:seasons_nested.players_nested.seasons_nested" => {"doc_count" => 47, "meta" => outer_meta}
              }
            }
          }

          response = resolve_target_nodes(<<~QUERY, aggs: aggs)
            target: team_aggregations {
              nodes {
                sub_aggregations {
                  seasons_nested {
                    nodes {
                      count_detail { approximate_value }
                      sub_aggregations {
                        players_nested {
                          nodes {
                            count_detail { approximate_value }
                            sub_aggregations {
                              seasons_nested {
                                nodes {
                                  count_detail { approximate_value }
                                }
                              }
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          QUERY

          expect(response).to eq [{
            "sub_aggregations" => {
              "seasons_nested" => {"nodes" => [{
                "count_detail" => {"approximate_value" => 4},
                "sub_aggregations" => {
                  "players_nested" => {"nodes" => [{
                    "count_detail" => {"approximate_value" => 25},
                    "sub_aggregations" => {
                      "seasons_nested" => {"nodes" => [{
                        "count_detail" => {"approximate_value" => 47}
                      }]}
                    }
                  }]}
                }
              }]}
            }
          }]
        end

        it "resolves filtered sub-aggregations" do
          aggs = {
            "target:seasons_nested" => {
              "meta" => outer_meta({"bucket_path" => ["seasons_nested:filtered"]}),
              "doc_count" => 423,
              "seasons_nested:filtered" => {"doc_count" => 57}
            }
          }

          response = resolve_target_nodes(<<~QUERY, aggs: aggs)
            target: team_aggregations {
              nodes {
                sub_aggregations {
                  seasons_nested(filter: {year: {gt: 2000}}) {
                    nodes {
                      count_detail {
                        approximate_value
                      }
                    }
                  }
                }
              }
            }
          QUERY

          expect(response).to eq [{
            "sub_aggregations" => {
              "seasons_nested" => {"nodes" => [{
                "count_detail" => {
                  "approximate_value" => 57
                }
              }]}
            }
          }]
        end

        it "treats an empty filter treating as `true`" do
          aggs = {
            "target:seasons_nested" => {"doc_count" => 423, "meta" => outer_meta}
          }

          response = resolve_target_nodes(<<~QUERY, aggs: aggs)
            target: team_aggregations {
              nodes {
                sub_aggregations {
                  seasons_nested(filter: {year: {gt: null}}) {
                    nodes {
                      count_detail {
                        approximate_value
                      }
                    }
                  }
                }
              }
            }
          QUERY

          expect(response).to eq [{
            "sub_aggregations" => {
              "seasons_nested" => {"nodes" => [{
                "count_detail" => {
                  "approximate_value" => 423
                }
              }]}
            }
          }]
        end

        it "resolves a filtered sub-aggregation under a filtered sub-aggregation" do
          aggs = {
            "target:current_players_nested" => {
              "meta" => outer_meta({"bucket_path" => ["current_players_nested:filtered"]}),
              "doc_count" => 5,
              "current_players_nested:filtered" => {
                "doc_count" => 3,
                "target:current_players_nested:current_players_nested.seasons_nested" => {
                  "meta" => outer_meta({"bucket_path" => ["seasons_nested:filtered"]}),
                  "doc_count" => 2,
                  "seasons_nested:filtered" => {"doc_count" => 1}
                }
              }
            }
          }

          response = resolve_target_nodes(<<~QUERY, aggs: aggs)
            target: team_aggregations {
              nodes {
                sub_aggregations {
                  current_players_nested(filter: {name: {equal_to_any_of: ["Bob"]}}) {
                    nodes {
                      count_detail {
                        approximate_value
                      }

                      sub_aggregations {
                        seasons_nested(filter: {year: {gt: 2000}}) {
                          nodes {
                            count_detail {
                              approximate_value
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          QUERY

          expect(response).to eq [{
            "sub_aggregations" => {
              "current_players_nested" => {"nodes" => [{
                "count_detail" => {"approximate_value" => 3},
                "sub_aggregations" => {
                  "seasons_nested" => {"nodes" => [{
                    "count_detail" => {"approximate_value" => 1}
                  }]}
                }
              }]}
            }
          }]
        end

        it "resolves a filtered sub-aggregation under an unfiltered sub-aggregation under a filtered sub-aggregation" do
          aggs = {
            "target:seasons_nested" => {
              "meta" => outer_meta({"bucket_path" => ["seasons_nested:filtered"]}),
              "doc_count" => 20,
              "seasons_nested:filtered" => {
                "doc_count" => 19,
                "target:seasons_nested:seasons_nested.players_nested" => {
                  "doc_count" => 18,
                  "meta" => outer_meta,
                  "target:seasons_nested:players_nested:seasons_nested.players_nested.seasons_nested" => {
                    "meta" => outer_meta({"bucket_path" => ["seasons_nested:filtered"]}),
                    "doc_count" => 12,
                    "seasons_nested:filtered" => {"doc_count" => 8}
                  }
                }
              }
            }
          }

          response = resolve_target_nodes(<<~QUERY, aggs: aggs)
            target: team_aggregations {
              nodes {
                sub_aggregations {
                  seasons_nested(filter: {year: {gt: 2000}}) {
                    nodes {
                      count_detail { approximate_value }
                      sub_aggregations {
                        players_nested {
                          nodes {
                            count_detail { approximate_value }
                            sub_aggregations {
                              seasons_nested(filter: {year: {gt: 2010}}) {
                                nodes {
                                  count_detail { approximate_value }
                                }
                              }
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          QUERY

          expect(response).to eq [{
            "sub_aggregations" => {
              "seasons_nested" => {"nodes" => [{
                "count_detail" => {"approximate_value" => 19},
                "sub_aggregations" => {
                  "players_nested" => {"nodes" => [{
                    "count_detail" => {"approximate_value" => 18},
                    "sub_aggregations" => {
                      "seasons_nested" => {"nodes" => [{
                        "count_detail" => {"approximate_value" => 8}
                      }]}
                    }
                  }]}
                }
              }]}
            }
          }]
        end

        context "with `count_detail` fields" do
          it "indicates the count is exact when no filtering or grouping has been applied" do
            aggs = {
              "target:seasons_nested" => {"doc_count" => 423, "meta" => outer_meta}
            }

            response = resolve_target_nodes(<<~QUERY, aggs: aggs)
              target: team_aggregations {
                nodes {
                  sub_aggregations {
                    seasons_nested {
                      nodes {
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

            expect(response.dig(0, "sub_aggregations", "seasons_nested", "nodes", 0, "count_detail")).to be_exactly_equal_to(423)
          end

          it "indicates the count is exact when filtering has been applied (but no grouping)" do
            aggs = {
              "target:seasons_nested" => {
                "meta" => outer_meta({"bucket_path" => ["seasons_nested:filtered"]}),
                "doc_count" => 423,
                "seasons_nested:filtered" => {"doc_count" => 57}
              }
            }

            response = resolve_target_nodes(<<~QUERY, aggs: aggs)
              target: team_aggregations {
                nodes {
                  sub_aggregations {
                    seasons_nested(filter: {year: {gt: 2000}}) {
                      nodes {
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

            expect(response.dig(0, "sub_aggregations", "seasons_nested", "nodes", 0, "count_detail")).to be_exactly_equal_to(57)
          end

          def be_exactly_equal_to(count)
            eq({"approximate_value" => count, "exact_value" => count, "upper_bound" => count})
          end
        end

        context "with aggregated values" do
          it "resolves ungrouped aggregated values" do
            aggs = {
              "target:current_players_nested" => {
                "doc_count" => 5,
                "meta" => outer_meta,
                "current_players_nested:current_players_nested.name:approximate_distinct_value_count" => {
                  "value" => 5
                }
              }
            }

            response = resolve_target_nodes(<<~QUERY, aggs: aggs)
              target: team_aggregations {
                nodes {
                  sub_aggregations {
                    current_players_nested {
                      nodes {
                        aggregated_values { name { approximate_distinct_value_count } }
                      }
                    }
                  }
                }
              }
            QUERY

            expect(response).to eq [{
              "sub_aggregations" => {
                "current_players_nested" => {
                  "nodes" => [
                    {
                      "aggregated_values" => {
                        "name" => {"approximate_distinct_value_count" => 5}
                      }
                    }
                  ]
                }
              }
            }]
          end

          it "uses GraphQL field aliases when resolving `aggregated_values` subfields" do
            aggs = {
              "target:current_players_nested" => {
                "doc_count" => 5,
                "meta" => outer_meta,
                "current_players_nested:current_players_nested.the_name:approximate_distinct_value_count" => {
                  "value" => 5
                }
              }
            }

            response = resolve_target_nodes(<<~QUERY, aggs: aggs)
              target: team_aggregations {
                nodes {
                  sub_aggregations {
                    current_players_nested {
                      nodes {
                        aggregated_values { the_name: name { approximate_distinct_value_count } }
                      }
                    }
                  }
                }
              }
            QUERY

            expect(response).to eq [{
              "sub_aggregations" => {
                "current_players_nested" => {
                  "nodes" => [
                    {
                      "aggregated_values" => {
                        "the_name" => {"approximate_distinct_value_count" => 5}
                      }
                    }
                  ]
                }
              }
            }]
          end

          context "with a `grouped_by` field which excludes all groupings via an `@include` directive" do
            it "returns an empty object for `grouped_by`" do
              aggs = {
                "target:current_players_nested" => {
                  "doc_count" => 5,
                  "meta" => outer_meta,
                  "current_players_nested:current_players_nested.name:approximate_distinct_value_count" => {
                    "value" => 3
                  }
                }
              }

              response = resolve_target_nodes(<<~QUERY, aggs: aggs)
                target: team_aggregations {
                  nodes {
                    sub_aggregations {
                      current_players_nested {
                        nodes {
                          grouped_by { name @include(if: false) }
                          count_detail { approximate_value }
                          aggregated_values { name { approximate_distinct_value_count } }
                        }
                      }
                    }
                  }
                }
              QUERY

              expect(response).to eq [{
                "sub_aggregations" => {
                  "current_players_nested" => {
                    "nodes" => [
                      {
                        "grouped_by" => {},
                        "count_detail" => {"approximate_value" => 5},
                        "aggregated_values" => {
                          "name" => {"approximate_distinct_value_count" => 3}
                        }
                      }
                    ]
                  }
                }
              }]
            end
          end
        end
      end
    end
  end
end
