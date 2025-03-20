# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphql/aggregation/query_adapter"
require "support/aggregations_helpers"
require "support/graphql"

module ElasticGraph
  class GraphQL
    module Aggregation
      RSpec.describe QueryAdapter, :query_adapter do
        include AggregationsHelpers

        attr_accessor :schema_artifacts

        before(:context) do
          self.schema_artifacts = generate_schema_artifacts { |schema| define_schema(schema) }
        end

        shared_examples_for "a query selecting nodes under aggregations" do |before_nodes:, after_nodes:|
          it "can build an aggregations object with 2 computations and no groupings" do
            aggregations = aggregations_from_datastore_query("Query", :widget_aggregations, <<~QUERY)
              query {
                widget_aggregations {
                  #{before_nodes}
                    aggregated_values {
                      amount_cents {
                        approximate_avg
                        exact_max
                        approximate_distinct_value_count
                      }
                    }
                  #{after_nodes}
                }
              }
            QUERY

            expect(aggregations).to eq([aggregation_query_of(name: "widget_aggregations", computations: [
              computation_of("amount_cents", :avg, computed_field_name: "approximate_avg"),
              computation_of("amount_cents", :max, computed_field_name: "exact_max"),
              computation_of("amount_cents", :cardinality, computed_field_name: "approximate_distinct_value_count")
            ])])
          end

          context "when the aggregated field has a `name_in_index` override" do
            before(:context) do
              self.schema_artifacts = generate_schema_artifacts { |schema| define_schema(schema, amount_cents_opts: {name_in_index: "amt_cts"}) }
            end

            it "respects the override in the generated aggregation hash" do
              aggregations = aggregations_from_datastore_query("Query", :widget_aggregations, <<~QUERY)
                query {
                  widget_aggregations {
                    #{before_nodes}
                      aggregated_values {
                        amount_cents {
                          approximate_avg
                          exact_max
                        }
                      }
                    #{after_nodes}
                  }
                }
              QUERY

              expect(aggregations).to eq([aggregation_query_of(name: "widget_aggregations", computations: [
                computation_of("amt_cts", :avg, computed_field_name: "approximate_avg", field_names_in_graphql_query: ["amount_cents"]),
                computation_of("amt_cts", :max, computed_field_name: "exact_max", field_names_in_graphql_query: ["amount_cents"])
              ])])
            end
          end

          it "can build an ungrouped aggregation hash from nested query fields" do
            aggregations = aggregations_from_datastore_query("Query", :widget_aggregations, <<~QUERY)
              query {
                widget_aggregations {
                  #{before_nodes}
                    aggregated_values {
                      cost {
                        amount_cents {
                          approximate_avg
                          exact_max
                        }
                      }
                    }
                  #{after_nodes}
                }
              }
            QUERY

            expect(aggregations).to eq([aggregation_query_of(name: "widget_aggregations", computations: [
              computation_of("cost", "amount_cents", :avg, computed_field_name: "approximate_avg"),
              computation_of("cost", "amount_cents", :max, computed_field_name: "exact_max")
            ])])
          end

          context "when a parent of the aggregated field has a `name_in_index` override" do
            before(:context) do
              self.schema_artifacts = generate_schema_artifacts { |schema| define_schema(schema, cost_opts: {name_in_index: "the_cost"}) }
            end

            it "respects the override in the generated aggregation hash" do
              aggregations = aggregations_from_datastore_query("Query", :widget_aggregations, <<~QUERY)
                query {
                  widget_aggregations {
                    #{before_nodes}
                      aggregated_values {
                        cost {
                          amount_cents {
                            approximate_avg
                            exact_max
                          }
                        }
                      }
                    #{after_nodes}
                  }
                }
              QUERY

              expect(aggregations).to eq([aggregation_query_of(name: "widget_aggregations", computations: [
                computation_of("the_cost", "amount_cents", :avg, computed_field_name: "approximate_avg", field_names_in_graphql_query: ["cost", "amount_cents"]),
                computation_of("the_cost", "amount_cents", :max, computed_field_name: "exact_max", field_names_in_graphql_query: ["cost", "amount_cents"])
              ])])
            end
          end

          context "with `sub_aggregations`" do
            before(:context) do
              self.schema_artifacts = CommonSpecHelpers.stock_schema_artifacts(for_context: :graphql)
            end

            it "can build sub-aggregations" do
              aggregations = aggregations_from_datastore_query("Query", :team_aggregations, <<~QUERY)
                query {
                  team_aggregations {
                    #{before_nodes}
                      sub_aggregations {
                        current_players_nested {
                          nodes {
                            count_detail {
                              approximate_value
                            }
                          }
                        }

                        seasons_nested {
                          nodes {
                            count_detail {
                              approximate_value
                            }
                          }
                        }
                      }
                    #{after_nodes}
                  }
                }
              QUERY

              expect(aggregations).to eq([aggregation_query_of(name: "team_aggregations", sub_aggregations: [
                nested_sub_aggregation_of(path_in_index: ["current_players_nested"], query: sub_aggregation_query_of(name: "current_players_nested", needs_doc_count: true)),
                nested_sub_aggregation_of(path_in_index: ["seasons_nested"], query: sub_aggregation_query_of(name: "seasons_nested", needs_doc_count: true))
              ])])
            end

            it "uses the injected grouping adapter on sub-aggregations" do
              build_sub_agg = lambda do |adapter|
                aggregations = aggregations_from_datastore_query("Query", :team_aggregations, <<~QUERY, sub_aggregation_grouping_adapter: adapter)
                  query {
                    team_aggregations {
                      #{before_nodes}
                        sub_aggregations {
                          current_players_nested {
                            nodes {
                              count_detail {
                                approximate_value
                              }
                            }
                          }

                          seasons_nested {
                            nodes {
                              count_detail {
                                approximate_value
                              }
                            }
                          }
                        }
                      #{after_nodes}
                    }
                  }
                QUERY

                aggregations.first.sub_aggregations.values.first
              end

              expect(build_sub_agg.call(NonCompositeGroupingAdapter).query.grouping_adapter).to eq NonCompositeGroupingAdapter
              expect(build_sub_agg.call(CompositeGroupingAdapter).query.grouping_adapter).to eq CompositeGroupingAdapter
            end

            it "determines it needs the doc count error if `upper_bound` or `exact_value` are requested, but not if `approximate_value` is requested" do
              needs_doc_count_error_by_count_field = %w[exact_value approximate_value upper_bound].to_h do |count_field|
                aggs = aggregations_from_datastore_query("Query", :team_aggregations, <<~QUERY)
                  query {
                    team_aggregations {
                      #{before_nodes}
                        sub_aggregations {
                          current_players_nested {
                            nodes {
                              count_detail {
                                #{count_field}
                              }
                            }
                          }
                        }
                      #{after_nodes}
                    }
                  }
                QUERY

                [count_field, aggs.first.sub_aggregations.values.first.query.needs_doc_count_error]
              end

              expect(needs_doc_count_error_by_count_field).to eq({
                "exact_value" => true,
                "approximate_value" => false,
                "upper_bound" => true
              })
            end

            it "builds a multi-part nested `path` for a `nested` field under extra object layers" do
              aggregations = aggregations_from_datastore_query("Query", :team_aggregations, <<~QUERY)
                query {
                  team_aggregations {
                    #{before_nodes}
                      sub_aggregations {
                        nested_fields {
                          current_players {
                            nodes {
                              count_detail {
                                approximate_value
                              }
                            }
                          }
                        }
                      }
                    #{after_nodes}
                  }
                }
              QUERY

              expect(aggregations).to eq([aggregation_query_of(name: "team_aggregations", sub_aggregations: [
                nested_sub_aggregation_of(
                  path_in_index: ["the_nested_fields", "current_players"],
                  query: sub_aggregation_query_of(name: "current_players", needs_doc_count: true),
                  path_in_graphql_query: ["nested_fields", "current_players"]
                )
              ])])
            end

            it "supports sub-aggregation fields having an alternate `name_in_index`" do
              aggregations = aggregations_from_datastore_query("Query", :team_aggregations, <<~QUERY)
                query {
                  team_aggregations {
                    #{before_nodes}
                      sub_aggregations {
                        nested_fields {
                          seasons {
                            nodes {
                              count_detail {
                                approximate_value
                              }
                            }
                          }
                        }
                      }
                    #{after_nodes}
                  }
                }
              QUERY

              expect(aggregations).to eq([aggregation_query_of(name: "team_aggregations", sub_aggregations: [
                nested_sub_aggregation_of(
                  path_in_index: ["the_nested_fields", "the_seasons"],
                  query: sub_aggregation_query_of(name: "seasons", needs_doc_count: true),
                  path_in_graphql_query: ["nested_fields", "seasons"]
                )
              ])])
            end

            it "supports sub-aggregations of sub-aggregations" do
              aggregations = aggregations_from_datastore_query("Query", :team_aggregations, <<~QUERY)
                query {
                  team_aggregations {
                    #{before_nodes}
                      sub_aggregations {
                        current_players_nested {
                          nodes {
                            count_detail {
                              approximate_value
                            }

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
                      }
                    #{after_nodes}
                  }
                }
              QUERY

              expect(aggregations).to eq([aggregation_query_of(name: "team_aggregations", sub_aggregations: [
                nested_sub_aggregation_of(path_in_index: ["current_players_nested"], query: sub_aggregation_query_of(
                  name: "current_players_nested",
                  needs_doc_count: true,
                  sub_aggregations: [
                    nested_sub_aggregation_of(path_in_index: ["current_players_nested", "seasons_nested"], query: sub_aggregation_query_of(name: "seasons_nested", needs_doc_count: true))
                  ]
                ))
              ])])
            end

            it "can handle sub-aggregation fields of the same name under parents of a different name" do
              aggregations = aggregations_from_datastore_query("Query", :team_aggregations, <<~QUERY)
                query {
                  team_aggregations {
                    #{before_nodes}
                      sub_aggregations {
                        nested_fields {
                          seasons {
                            nodes {
                              aggregated_values {
                                year { exact_min }
                              }
                            }
                          }
                        }

                        nested_fields2 {
                          seasons {
                            nodes {
                              aggregated_values {
                                year { exact_min }
                              }
                            }
                          }
                        }
                      }
                    #{after_nodes}
                  }
                }
              QUERY

              expect(aggregations).to eq [aggregation_query_of(name: "team_aggregations", sub_aggregations: [
                nested_sub_aggregation_of(
                  path_in_graphql_query: ["nested_fields", "seasons"],
                  path_in_index: ["the_nested_fields", "the_seasons"],
                  query: sub_aggregation_query_of(
                    name: "seasons",
                    computations: [
                      computation_of(
                        "the_nested_fields", "the_seasons", "year", :min,
                        computed_field_name: "exact_min",
                        field_names_in_graphql_query: ["nested_fields", "seasons", "year"]
                      )
                    ]
                  )
                ),
                nested_sub_aggregation_of(
                  path_in_graphql_query: ["nested_fields2", "seasons"],
                  path_in_index: ["nested_fields2", "the_seasons"],
                  query: sub_aggregation_query_of(
                    name: "seasons",
                    computations: [
                      computation_of(
                        "nested_fields2", "the_seasons", "year", :min,
                        computed_field_name: "exact_min",
                        field_names_in_graphql_query: ["nested_fields2", "seasons", "year"]
                      )
                    ]
                  )
                )
              ])]
            end

            it "allows aliases to be used on a sub-aggregations field to request multiple differing sub-aggregations" do
              aggregations = aggregations_from_datastore_query("Query", :team_aggregations, <<~QUERY)
                query {
                  team_aggregations {
                    #{before_nodes}
                      sub_aggregations {
                        players1: current_players_nested {
                          nodes {
                            count_detail {
                              approximate_value
                            }
                          }
                        }

                        players2: current_players_nested {
                          nodes {
                            count_detail {
                              exact_value
                            }
                          }
                        }
                      }
                    #{after_nodes}
                  }
                }
              QUERY

              expect(aggregations).to eq([aggregation_query_of(name: "team_aggregations", sub_aggregations: [
                nested_sub_aggregation_of(
                  path_in_index: ["current_players_nested"],
                  path_in_graphql_query: ["players1"],
                  query: sub_aggregation_query_of(name: "players1", needs_doc_count: true)
                ),
                nested_sub_aggregation_of(
                  path_in_index: ["current_players_nested"],
                  path_in_graphql_query: ["players2"],
                  query: sub_aggregation_query_of(name: "players2", needs_doc_count_error: true, needs_doc_count: true)
                )
              ])])
            end

            it "builds a `filter` on a sub-aggregation when present on the GraphQL query" do
              aggregations = aggregations_from_datastore_query("Query", :team_aggregations, <<~QUERY)
                query {
                  team_aggregations {
                    #{before_nodes}
                      sub_aggregations {
                        seasons_nested(filter: {year: {gt: 2000}}) {
                          nodes {
                            count_detail {
                              approximate_value
                            }
                          }
                        }
                      }
                    #{after_nodes}
                  }
                }
              QUERY

              expect(aggregations).to eq([aggregation_query_of(name: "team_aggregations", sub_aggregations: [
                nested_sub_aggregation_of(path_in_index: ["seasons_nested"], query: sub_aggregation_query_of(
                  name: "seasons_nested",
                  needs_doc_count: true,
                  filter: {"year" => {"gt" => 2000}}
                ))
              ])])
            end

            it "builds `groupings` at any level of sub-aggregation when `groupedBy` is present in the query at that level" do
              aggregations = aggregations_from_datastore_query("Query", :team_aggregations, <<~QUERY)
                query {
                  team_aggregations {
                    #{before_nodes}
                      sub_aggregations {
                        seasons_nested {
                          nodes {
                            grouped_by {
                              year
                              note
                              started_at {
                                as_date_time(truncation_unit: YEAR)
                              }
                            }

                            sub_aggregations {
                              players_nested {
                                nodes {
                                  grouped_by {
                                    name
                                  }
                                }
                              }
                            }
                          }
                        }
                      }
                    #{after_nodes}
                  }
                }
              QUERY

              expect(aggregations).to eq([aggregation_query_of(name: "team_aggregations", sub_aggregations: [
                nested_sub_aggregation_of(path_in_index: ["seasons_nested"], query: sub_aggregation_query_of(
                  name: "seasons_nested",
                  groupings: [
                    field_term_grouping_of("seasons_nested", "year"),
                    field_term_grouping_of("seasons_nested", "notes", field_names_in_graphql_query: ["seasons_nested", "note"]),
                    date_histogram_grouping_of("seasons_nested", "started_at", "year", field_names_in_graphql_query: ["seasons_nested", "started_at", "as_date_time"])
                  ],
                  sub_aggregations: [
                    nested_sub_aggregation_of(path_in_index: ["seasons_nested", "players_nested"], query: sub_aggregation_query_of(
                      name: "players_nested",
                      groupings: [field_term_grouping_of("seasons_nested", "players_nested", "name")]
                    ))
                  ]
                ))
              ])])
            end

            it "builds legacy date time `groupings` at any level of sub-aggregation when `groupedBy` is present in the query at that level" do
              aggregations = aggregations_from_datastore_query("Query", :team_aggregations, <<~QUERY)
                query {
                  team_aggregations {
                    #{before_nodes}
                      sub_aggregations {
                        seasons_nested {
                          nodes {
                            grouped_by {
                              year
                              note
                              started_at_legacy(granularity: YEAR)
                            }

                            sub_aggregations {
                              players_nested {
                                nodes {
                                  grouped_by {
                                    name
                                  }
                                }
                              }
                            }
                          }
                        }
                      }
                    #{after_nodes}
                  }
                }
              QUERY

              expect(aggregations).to eq([aggregation_query_of(name: "team_aggregations", sub_aggregations: [
                nested_sub_aggregation_of(path_in_index: ["seasons_nested"], query: sub_aggregation_query_of(
                  name: "seasons_nested",
                  groupings: [
                    field_term_grouping_of("seasons_nested", "year"),
                    field_term_grouping_of("seasons_nested", "notes", field_names_in_graphql_query: ["seasons_nested", "note"]),
                    date_histogram_grouping_of("seasons_nested", "started_at", "year", field_names_in_graphql_query: ["seasons_nested", "started_at_legacy"])
                  ],
                  sub_aggregations: [
                    nested_sub_aggregation_of(path_in_index: ["seasons_nested", "players_nested"], query: sub_aggregation_query_of(
                      name: "players_nested",
                      groupings: [field_term_grouping_of("seasons_nested", "players_nested", "name")]
                    ))
                  ]
                ))
              ])])
            end

            it "does not support multiple aliases on `nodes` or `grouped_by` because if different `grouped_by` fields are selected we can have conflicting grouping requirements" do
              error = single_graphql_error_for(<<~QUERY)
                query {
                  team_aggregations {
                    #{before_nodes}
                      sub_aggregations {
                        seasons_nested {
                          by_year: nodes {
                            grouped_by { year }
                            count_detail { approximate_value }
                          }

                          by_note: nodes {
                            grouped_by { note }
                            count_detail { approximate_value }
                          }
                        }
                      }
                    #{after_nodes}
                  }
                }
              QUERY

              expect(error["message"]).to include("more than one `nodes` selection under `seasons_nested` (`by_year`, `by_note`),")

              error = single_graphql_error_for(<<~QUERY)
                query {
                  team_aggregations {
                    #{before_nodes}
                      sub_aggregations {
                        seasons_nested {
                          nodes {
                            by_year: grouped_by { year }
                            by_note: grouped_by { note }
                            count_detail { approximate_value }
                          }
                        }
                      }
                    #{after_nodes}
                  }
                }
              QUERY

              expect(error["message"]).to include("more than one `grouped_by` selection under `seasons_nested` (`by_year`, `by_note`),")
            end

            it "builds `computations` at any level of sub-aggregation when `aggregated_values` is present in the query at that level" do
              aggregations = aggregations_from_datastore_query("Query", :team_aggregations, <<~QUERY)
                query {
                  team_aggregations {
                    #{before_nodes}
                      sub_aggregations {
                        seasons_nested {
                          nodes {
                            aggregated_values {
                              year { exact_min }
                              record {
                                wins {
                                  exact_max
                                  approximate_avg
                                }
                              }
                            }

                            sub_aggregations {
                              players_nested {
                                nodes {
                                  aggregated_values {
                                    nicknames {
                                      approximate_distinct_value_count
                                    }
                                  }
                                }
                              }
                            }
                          }
                        }
                      }
                    #{after_nodes}
                  }
                }
              QUERY

              expect(aggregations).to eq([aggregation_query_of(name: "team_aggregations", sub_aggregations: [
                nested_sub_aggregation_of(path_in_index: ["seasons_nested"], query: sub_aggregation_query_of(
                  name: "seasons_nested",
                  computations: [
                    computation_of("seasons_nested", "year", :min, computed_field_name: "exact_min"),
                    computation_of("seasons_nested", "the_record", "win_count", :max, computed_field_name: "exact_max", field_names_in_graphql_query: ["seasons_nested", "record", "wins"]),
                    computation_of("seasons_nested", "the_record", "win_count", :avg, computed_field_name: "approximate_avg", field_names_in_graphql_query: ["seasons_nested", "record", "wins"])
                  ],
                  sub_aggregations: [
                    nested_sub_aggregation_of(path_in_index: ["seasons_nested", "players_nested"], query: sub_aggregation_query_of(
                      name: "players_nested",
                      computations: [
                        computation_of("seasons_nested", "players_nested", "nicknames", :cardinality, computed_field_name: "approximate_distinct_value_count")
                      ]
                    ))
                  ]
                ))
              ])])
            end

            describe "paginator.desired_page_size" do
              include GraphQLSupport

              it "is set based on the `first:` argument" do
                sub_agg_query = build_sub_aggregation_query({first: 30}, default_page_size: 47, max_page_size: 212)

                expect(sub_agg_query.paginator.desired_page_size).to eq(30)
              end

              it "is set to the configured `default_page_size` if not specified in the query" do
                sub_agg_query = build_sub_aggregation_query({}, default_page_size: 47, max_page_size: 212)

                expect(sub_agg_query.paginator.desired_page_size).to eq(47)
              end

              it "is set to the configured `default_page_size` if set to `null` in the query" do
                sub_agg_query = build_sub_aggregation_query({first: nil}, default_page_size: 47, max_page_size: 212)

                expect(sub_agg_query.paginator.desired_page_size).to eq(47)
              end

              it "is limited based on the configured `max_page_size`" do
                sub_agg_query = build_sub_aggregation_query({first: 300}, default_page_size: 47, max_page_size: 212)

                expect(sub_agg_query.paginator.desired_page_size).to eq(212)
              end

              it "return an error if `first` is specified as a negative number in the query" do
                sub_agg_query = build_sub_aggregation_query({first: -10}, default_page_size: 47, max_page_size: 212)

                expect {
                  sub_agg_query.paginator.desired_page_size
                }.to raise_error ::GraphQL::ExecutionError, "`first` cannot be negative, but is -10."
              end

              def build_sub_aggregation_query(args, default_page_size:, max_page_size:)
                aggregations = aggregations_from_datastore_query(
                  "Query",
                  :team_aggregations,
                  query_for(**args),
                  default_page_size: default_page_size,
                  max_page_size: max_page_size
                )

                expect(aggregations.size).to eq(1)
                expect(aggregations.first.sub_aggregations.size).to eq(1)
                aggregations.first.sub_aggregations.values.first.query
              end

              define_method :query_for do |**args|
                <<~QUERY
                  query {
                    team_aggregations {
                      #{before_nodes}
                        sub_aggregations {
                          seasons_nested#{graphql_args(args)} {
                            nodes {
                              grouped_by { year }
                              count_detail { approximate_value }
                            }
                          }
                        }
                      #{after_nodes}
                    }
                  }
                QUERY
              end
            end

            context "when filtering on a field that has an alternate `name_in_index`" do
              before(:context) do
                self.schema_artifacts = generate_schema_artifacts { |schema| define_schema(schema) }
              end

              it "respects the `name_in_index` when parsing a filter" do
                aggregations = aggregations_from_datastore_query("Query", :widget_aggregations, <<~QUERY)
                  query {
                    widget_aggregations {
                      #{before_nodes}
                        sub_aggregations {
                          costs(filter: {amount: {gt: 2000}}) {
                            nodes {
                              count_detail {
                                approximate_value
                              }
                            }
                          }
                        }
                      #{after_nodes}
                    }
                  }
                QUERY

                expect(aggregations).to eq([aggregation_query_of(name: "widget_aggregations", sub_aggregations: [
                  nested_sub_aggregation_of(path_in_index: ["costs"], query: sub_aggregation_query_of(
                    name: "costs",
                    needs_doc_count: true,
                    filter: {"amount_in_index" => {"gt" => 2000}}
                  ))
                ])])
              end
            end
          end

          context "aggregations with `legacy_grouping_schema`" do
            before(:context) do
              self.schema_artifacts = generate_schema_artifacts { |schema| define_schema(schema, legacy_grouping_schema: true) }
            end
            it "can build an aggregations object with multiple groupings and computations" do
              aggregations = aggregations_from_datastore_query("Query", :widget_aggregations, <<~QUERY)
                query {
                  widget_aggregations {
                    #{before_nodes}
                      grouped_by {
                        size
                        color
                        created_at(granularity: DAY)
                      }

                      aggregated_values {
                        amount_cents {
                          approximate_avg
                          exact_max
                        }
                      }
                    #{after_nodes}
                  }
                }
              QUERY

              expect(aggregations).to eq([aggregation_query_of(
                name: "widget_aggregations",
                computations: [
                  computation_of("amount_cents", :avg, computed_field_name: "approximate_avg"),
                  computation_of("amount_cents", :max, computed_field_name: "exact_max")
                ],
                groupings: [
                  field_term_grouping_of("size"),
                  field_term_grouping_of("color"),
                  date_histogram_grouping_of("created_at", "day")
                ]
              )])
            end

            it "respects the `time_zone` option" do
              aggregations = aggregations_from_datastore_query("Query", :widget_aggregations, <<~QUERY)
                query {
                  widget_aggregations {
                    #{before_nodes}
                      grouped_by {
                        created_at(granularity: DAY, time_zone: "America/Los_Angeles")
                      }

                      count
                    #{after_nodes}
                  }
                }
              QUERY

              expect(aggregations).to eq([aggregation_query_of(
                name: "widget_aggregations",
                computations: [],
                needs_doc_count: true,
                groupings: [
                  date_histogram_grouping_of("created_at", "day", time_zone: "America/Los_Angeles")
                ]
              )])
            end

            it "respects the `offset` option" do
              aggregations = aggregations_from_datastore_query("Query", :widget_aggregations, <<~QUERY)
                query {
                  widget_aggregations {
                    #{before_nodes}
                      grouped_by {
                        created_at(granularity: DAY, offset: {amount: -12, unit: HOUR})
                      }

                      count
                    #{after_nodes}
                  }
                }
              QUERY

              expect(aggregations).to eq([aggregation_query_of(
                name: "widget_aggregations",
                computations: [],
                needs_doc_count: true,
                groupings: [
                  date_histogram_grouping_of("created_at", "day", time_zone: "UTC", offset: "-12h")
                ]
              )])
            end

            it "supports `Date` field groupings, allowing them to have no `time_zone` argument" do
              aggregations = aggregations_from_datastore_query("Query", :widget_aggregations, <<~QUERY)
                query {
                  widget_aggregations {
                    #{before_nodes}
                      grouped_by {
                        created_on(granularity: MONTH)
                      }

                      count
                    #{after_nodes}
                  }
                }
              QUERY

              expect(aggregations).to eq([aggregation_query_of(
                name: "widget_aggregations",
                computations: [],
                needs_doc_count: true,
                groupings: [
                  date_histogram_grouping_of("created_on", "month", time_zone: nil)
                ]
              )])
            end

            it "supports `offsetDays` on `Date` field groupings" do
              aggregations = aggregations_from_datastore_query("Query", :widget_aggregations, <<~QUERY)
                query {
                  widget_aggregations {
                    #{before_nodes}
                      grouped_by {
                        created_on(granularity: MONTH, offset_days: -12)
                      }

                      count
                    #{after_nodes}
                  }
                }
              QUERY

              expect(aggregations).to eq([aggregation_query_of(
                name: "widget_aggregations",
                computations: [],
                needs_doc_count: true,
                groupings: [
                  date_histogram_grouping_of("created_on", "month", time_zone: nil, offset: "-12d")
                ]
              )])
            end
          end

          context "aggregations without `legacy_grouping_schema`" do
            it "can build an aggregations object with multiple groupings and computations" do
              aggregations = aggregations_from_datastore_query("Query", :widget_aggregations, <<~QUERY)
                query {
                  widget_aggregations {
                    #{before_nodes}
                      grouped_by {
                        size
                        color
                        created_at {
                          as_date_time(truncation_unit: DAY)
                        }
                      }

                      aggregated_values {
                        amount_cents {
                          approximate_avg
                          exact_max
                        }
                      }
                    #{after_nodes}
                  }
                }
              QUERY

              expect(aggregations).to eq([aggregation_query_of(
                name: "widget_aggregations",
                computations: [
                  computation_of("amount_cents", :avg, computed_field_name: "approximate_avg"),
                  computation_of("amount_cents", :max, computed_field_name: "exact_max")
                ],
                groupings: [
                  field_term_grouping_of("size"),
                  field_term_grouping_of("color"),
                  date_histogram_grouping_of("created_at", "day", graphql_subfield: "as_date_time")
                ]
              )])
            end

            it "can build an aggregations object with every `DateTimeGroupedBy` subfield" do
              # Verify that the fields we request in the query below are in fact all the subfields
              expect(sub_fields_of("DateTimeGroupedBy")).to contain_exactly("as_date_time", "as_date", "as_time_of_day", "as_day_of_week")

              aggregations = aggregations_from_datastore_query("Query", :widget_aggregations, <<~QUERY)
                query {
                  widget_aggregations {
                    #{before_nodes}
                      grouped_by {
                        created_at {
                          as_date_time(truncation_unit: DAY)
                          as_date(truncation_unit: YEAR, time_zone: "America/Los_Angeles", offset: {amount: 30, unit: DAY})
                          as_time_of_day(truncation_unit: SECOND, time_zone: "America/Los_Angeles", offset: {amount: 60, unit: MINUTE})
                          as_day_of_week(time_zone: "America/Los_Angeles", offset: {amount: 3, unit: HOUR})
                        }
                      }

                      count
                    #{after_nodes}
                  }
                }
              QUERY

              expect(aggregations).to eq([aggregation_query_of(
                name: "widget_aggregations",
                computations: [],
                needs_doc_count: true,
                groupings: [
                  date_histogram_grouping_of("created_at", "day", time_zone: "UTC", graphql_subfield: "as_date_time"),
                  date_histogram_grouping_of("created_at", "year", time_zone: "America/Los_Angeles", offset: "30d", graphql_subfield: "as_date"),
                  as_time_of_day_grouping_of("created_at", "second", time_zone: "America/Los_Angeles", offset_ms: 3_600_000, graphql_subfield: "as_time_of_day"),
                  as_day_of_week_grouping_of("created_at", time_zone: "America/Los_Angeles", offset_ms: 10_800_000, graphql_subfield: "as_day_of_week")
                ]
              )])
            end

            it "sets defaults correctly when `as_day_of_week` for time_zone and offset_ms" do
              aggregations = aggregations_from_datastore_query("Query", :widget_aggregations, <<~QUERY)
                query {
                  widget_aggregations {
                    #{before_nodes}
                      grouped_by {
                        created_at {
                          as_day_of_week
                        }
                      }

                      count
                    #{after_nodes}
                  }
                }
              QUERY

              expect(aggregations).to eq([aggregation_query_of(
                name: "widget_aggregations",
                computations: [],
                needs_doc_count: true,
                groupings: [
                  as_day_of_week_grouping_of("created_at", time_zone: "UTC", offset_ms: 0, graphql_subfield: "as_day_of_week")
                ]
              )])
            end

            it "sets defaults correctly when `as_time_of_day` for time_zone and offset_ms" do
              aggregations = aggregations_from_datastore_query("Query", :widget_aggregations, <<~QUERY)
                query {
                  widget_aggregations {
                    #{before_nodes}
                      grouped_by {
                        created_at {
                          as_time_of_day(truncation_unit: HOUR)
                        }
                      }

                      count
                    #{after_nodes}
                  }
                }
              QUERY

              expect(aggregations).to eq([aggregation_query_of(
                name: "widget_aggregations",
                computations: [],
                needs_doc_count: true,
                groupings: [
                  as_time_of_day_grouping_of("created_at", "hour", time_zone: "UTC", offset_ms: 0, graphql_subfield: "as_time_of_day")
                ]
              )])
            end

            it "respects the `time_zone` option" do
              aggregations = aggregations_from_datastore_query("Query", :widget_aggregations, <<~QUERY)
                query {
                  widget_aggregations {
                    #{before_nodes}
                      grouped_by {
                        created_at {
                          as_date_time(truncation_unit: DAY, time_zone: "America/Los_Angeles")
                        }
                      }

                      count
                    #{after_nodes}
                  }
                }
              QUERY

              expect(aggregations).to eq([aggregation_query_of(
                name: "widget_aggregations",
                computations: [],
                needs_doc_count: true,
                groupings: [
                  date_histogram_grouping_of("created_at", "day", time_zone: "America/Los_Angeles", graphql_subfield: "as_date_time")
                ]
              )])
            end

            it "respects the `offset` option" do
              aggregations = aggregations_from_datastore_query("Query", :widget_aggregations, <<~QUERY)
                query {
                  widget_aggregations {
                    #{before_nodes}
                      grouped_by {
                        created_at {
                          as_date_time(truncation_unit: DAY, offset: {amount: -12, unit: HOUR})
                        }
                      }

                      count
                    #{after_nodes}
                  }
                }
              QUERY

              expect(aggregations).to eq([aggregation_query_of(
                name: "widget_aggregations",
                computations: [],
                needs_doc_count: true,
                groupings: [
                  date_histogram_grouping_of("created_at", "day", time_zone: "UTC", offset: "-12h", graphql_subfield: "as_date_time")
                ]
              )])
            end

            it "supports `Date` field groupings, allowing them to have no `time_zone` argument" do
              aggregations = aggregations_from_datastore_query("Query", :widget_aggregations, <<~QUERY)
                query {
                  widget_aggregations {
                    #{before_nodes}
                      grouped_by {
                        created_on {
                          as_date(truncation_unit: MONTH)
                        }
                      }

                      count
                    #{after_nodes}
                  }
                }
              QUERY

              expect(aggregations).to eq([aggregation_query_of(
                name: "widget_aggregations",
                computations: [],
                needs_doc_count: true,
                groupings: [
                  date_histogram_grouping_of("created_on", "month", time_zone: "UTC", graphql_subfield: "as_date")
                ]
              )])
            end

            it "can build an aggregations object with every `DateGroupedBy` subfield" do
              # Verify that the fields we request in the query below are in fact all the subfields
              expect(sub_fields_of("DateGroupedBy")).to contain_exactly("as_date", "as_day_of_week")

              aggregations = aggregations_from_datastore_query("Query", :widget_aggregations, <<~QUERY)
                query {
                  widget_aggregations {
                    #{before_nodes}
                      grouped_by {
                        created_on {
                          as_date(truncation_unit: YEAR, offset: {amount: 30, unit: DAY})
                          as_day_of_week(offset: {amount: 1, unit: DAY})
                        }
                      }

                      count
                    #{after_nodes}
                  }
                }
              QUERY

              expect(aggregations).to eq([aggregation_query_of(
                name: "widget_aggregations",
                computations: [],
                needs_doc_count: true,
                groupings: [
                  date_histogram_grouping_of("created_on", "year", time_zone: "UTC", offset: "30d", graphql_subfield: "as_date"),
                  as_day_of_week_grouping_of("created_on", offset_ms: 86_400_000, graphql_subfield: "as_day_of_week")
                ]
              )])
            end

            it "supports `offset` on `Date` field groupings" do
              aggregations = aggregations_from_datastore_query("Query", :widget_aggregations, <<~QUERY)
                query {
                  widget_aggregations {
                    #{before_nodes}
                      grouped_by {
                        created_on {
                          as_date(truncation_unit: MONTH, offset: {amount: -12, unit: DAY})
                        }
                      }

                      count
                    #{after_nodes}
                  }
                }
              QUERY

              expect(aggregations).to eq([aggregation_query_of(
                name: "widget_aggregations",
                computations: [],
                needs_doc_count: true,
                groupings: [
                  date_histogram_grouping_of("created_on", "month", time_zone: "UTC", offset: "-12d", graphql_subfield: "as_date")
                ]
              )])
            end
          end

          it "omits grouping fields that have a `@skip(if: true)` directive" do
            aggregations = aggregations_from_datastore_query("Query", :widget_aggregations, <<~QUERY)
              query {
                widget_aggregations {
                  #{before_nodes}
                    grouped_by {
                      size @skip(if: true)
                      color @skip(if: false)
                      created_at {
                        as_date_time(truncation_unit: DAY)
                      }
                    }

                    aggregated_values {
                      amount_cents {
                        exact_max
                      }
                    }
                  #{after_nodes}
                }
              }
            QUERY

            expect(aggregations).to eq([aggregation_query_of(
              name: "widget_aggregations",
              computations: [
                computation_of("amount_cents", :max, computed_field_name: "exact_max")
              ],
              groupings: [
                field_term_grouping_of("color"),
                date_histogram_grouping_of("created_at", "day", graphql_subfield: "as_date_time")
              ]
            )])
          end

          it "omits grouping fields that have an `@include(if: false)` directive" do
            aggregations = aggregations_from_datastore_query("Query", :widget_aggregations, <<~QUERY)
              query {
                widget_aggregations {
                  #{before_nodes}
                    grouped_by {
                      size @include(if: true)
                      color @include(if: false)
                      created_at {
                        as_date_time(truncation_unit: DAY)
                      }
                    }

                    aggregated_values {
                      amount_cents {
                        exact_max
                      }
                    }
                  #{after_nodes}
                }
              }
            QUERY

            expect(aggregations).to eq([aggregation_query_of(
              name: "widget_aggregations",
              computations: [
                computation_of("amount_cents", :max, computed_field_name: "exact_max")
              ],
              groupings: [
                field_term_grouping_of("size"),
                date_histogram_grouping_of("created_at", "day", graphql_subfield: "as_date_time")
              ]
            )])
          end

          it "omits computation fields that have a `@skip(if: true)` directive" do
            aggregations = aggregations_from_datastore_query("Query", :widget_aggregations, <<~QUERY)
              query {
                widget_aggregations {
                  #{before_nodes}
                    grouped_by {
                      size
                    }

                    aggregated_values {
                      amount_cents {
                        approximate_avg @skip(if: true)
                        exact_max @skip(if: false)
                        exact_min
                      }
                    }
                  #{after_nodes}
                }
              }
            QUERY

            expect(aggregations).to eq([aggregation_query_of(
              name: "widget_aggregations",
              computations: [
                computation_of("amount_cents", :max, computed_field_name: "exact_max"),
                computation_of("amount_cents", :min, computed_field_name: "exact_min")
              ],
              groupings: [
                field_term_grouping_of("size")
              ]
            )])
          end

          it "omits computation fields that have a `@include(if: true)` directive" do
            aggregations = aggregations_from_datastore_query("Query", :widget_aggregations, <<~QUERY)
              query {
                widget_aggregations {
                  #{before_nodes}
                    grouped_by {
                      size
                    }

                    aggregated_values {
                      amount_cents {
                        approximate_avg @include(if: true)
                        exact_max @include(if: false)
                        exact_min
                      }
                    }
                  #{after_nodes}
                }
              }
            QUERY

            expect(aggregations).to eq([aggregation_query_of(
              name: "widget_aggregations",
              computations: [
                computation_of("amount_cents", :avg, computed_field_name: "approximate_avg"),
                computation_of("amount_cents", :min, computed_field_name: "exact_min")
              ],
              groupings: [
                field_term_grouping_of("size")
              ]
            )])
          end

          it "sets `needs_doc_count` to false if the count field has a `@skip(if: true)` directive" do
            skip_false = aggregations_from_datastore_query("Query", :widget_aggregations, <<~QUERY).first
              query {
                widget_aggregations {
                  #{before_nodes}
                    grouped_by {
                      size
                    }

                    count @skip(if: false)
                  #{after_nodes}
                }
              }
            QUERY

            expect(skip_false.needs_doc_count).to eq true

            skip_true = aggregations_from_datastore_query("Query", :widget_aggregations, <<~QUERY).first
              query {
                widget_aggregations {
                  #{before_nodes}
                    grouped_by {
                      size
                    }

                    count @skip(if: true)
                  #{after_nodes}
                }
              }
            QUERY

            expect(skip_true.needs_doc_count).to eq false
          end

          it "sets `needs_doc_count` to false if the count field has an `@include(if: false)` directive" do
            include_false = aggregations_from_datastore_query("Query", :widget_aggregations, <<~QUERY).first
              query {
                widget_aggregations {
                  #{before_nodes}
                    grouped_by {
                      size
                    }

                    count @include(if: false)
                  #{after_nodes}
                }
              }
            QUERY

            expect(include_false.needs_doc_count).to eq false

            include_true = aggregations_from_datastore_query("Query", :widget_aggregations, <<~QUERY).first
              query {
                widget_aggregations {
                  #{before_nodes}
                    grouped_by {
                      size
                    }

                    count @include(if: true)
                  #{after_nodes}
                }
              }
            QUERY

            expect(include_true.needs_doc_count).to eq true
          end

          it "handles multiple aggregation aliases directly on the aggregation field (e.g. to support grouping on different dimensions)" do
            aggs_map = aggregations_by_field_name_for(<<~QUERY)
              query {
                by_day: widget_aggregations(first: 1) {
                  #{before_nodes}
                    grouped_by {
                      created_at {
                        as_date_time(truncation_unit: DAY)
                      }
                    }

                    aggregated_values {
                      amount_cents {
                        approximate_avg
                      }
                    }
                  #{after_nodes}
                }

                by_month: widget_aggregations(last: 3) {
                  #{before_nodes}
                    grouped_by {
                      created_at {
                        as_date_time(truncation_unit: MONTH)
                      }
                    }

                    aggregated_values {
                      amount_cents {
                        exact_max
                      }
                    }
                  #{after_nodes}
                }

                just_count: widget_aggregations {
                  #{before_nodes}
                    count
                  #{after_nodes}
                }

                just_sum: widget_aggregations {
                  #{before_nodes}
                    aggregated_values {
                      amount_cents {
                        exact_sum
                      }
                    }
                  #{after_nodes}
                }
              }
            QUERY

            aggs_map = aggs_map.transform_keys { |qualified_field_name| qualified_field_name.split(".").last }

            expect(aggs_map.keys).to contain_exactly("by_day", "by_month", "just_count", "just_sum")

            expect(aggs_map["by_day"]).to eq aggregation_query_of(
              name: "by_day",
              groupings: [date_histogram_grouping_of("created_at", "day", graphql_subfield: "as_date_time")],
              computations: [computation_of("amount_cents", :avg, computed_field_name: "approximate_avg")],
              first: 1
            )

            expect(aggs_map["by_month"]).to eq aggregation_query_of(
              name: "by_month",
              groupings: [date_histogram_grouping_of("created_at", "month", graphql_subfield: "as_date_time")],
              computations: [computation_of("amount_cents", :max, computed_field_name: "exact_max")],
              last: 3
            )

            expect(aggs_map["just_count"]).to eq aggregation_query_of(
              name: "just_count",
              needs_doc_count: true
            )

            expect(aggs_map["just_sum"]).to eq aggregation_query_of(
              name: "just_sum",
              computations: [computation_of("amount_cents", :sum, computed_field_name: "exact_sum")]
            )
          end

          it "does not support multiple unaliased aggregations because if different `grouped_by` fields are selected under `node` we can have conflicting grouping requirements" do
            error = single_graphql_error_for(<<~QUERY)
              query {
                widget_aggregations {
                  #{before_nodes}
                    grouped_by { size }
                    count
                  #{after_nodes}
                }

                widget_aggregations {
                  #{before_nodes}
                    grouped_by { color }
                    count
                  #{after_nodes}
                }
              }
            QUERY

            expect(error["message"]).to include("more than one `widget_aggregations` selection with the same name (`widget_aggregations`, `widget_aggregations`)")
          end

          it "does not support multiple aggregations with the same alias because if different `grouped_by` fields are selected under `node` we can have conflicting grouping requirements" do
            error = single_graphql_error_for(<<~QUERY)
              query {
                w: widget_aggregations {
                  #{before_nodes}
                    grouped_by { size }
                    count
                  #{after_nodes}
                }

                w: widget_aggregations {
                  #{before_nodes}
                    grouped_by { color }
                    count
                  #{after_nodes}
                }
              }
            QUERY

            expect(error["message"]).to include("more than one `widget_aggregations` selection with the same name (`w`, `w`)")
          end

          it "does not support multiple aliases on `grouped_by` because we need a single list of fields to group by" do
            error = single_graphql_error_for(<<~QUERY)
              query {
                aggs: widget_aggregations {
                  #{before_nodes}
                    by_size: grouped_by { size }
                    by_color: grouped_by { color }
                    count
                  #{after_nodes}
                }
              }
            QUERY

            expect(error["message"]).to include("more than one `grouped_by` selection under `aggs` (`by_size`, `by_color`)")
          end

          it "does not support multiple unaliased `grouped_by`s because we need a single list of fields to group by" do
            error = single_graphql_error_for(<<~QUERY)
              query {
                aggs: widget_aggregations {
                  #{before_nodes}
                    grouped_by { size }
                    grouped_by { color }
                    count
                  #{after_nodes}
                }
              }
            QUERY

            expect(error["message"]).to include("more than one `grouped_by` selection under `aggs` (`grouped_by`, `grouped_by`)")
          end

          it "supports multiple aliases on `count` since that doesn't interfere with grouping" do
            aggregations = aggregations_from_datastore_query("Query", :widget_aggregations, <<~QUERY)
              query {
                widget_aggregations {
                  #{before_nodes}
                    count1: count
                    count2: count

                    aggregated_values {
                      amount_cents {
                        approximate_avg
                      }
                    }
                  #{after_nodes}
                }
              }
            QUERY

            expect(aggregations).to eq([aggregation_query_of(
              name: "widget_aggregations",
              computations: [computation_of("amount_cents", :avg, computed_field_name: "approximate_avg")],
              needs_doc_count: true
            )])
          end

          it "supports multiple aliases on `aggregated_values` since that doesn't interfere with grouping" do
            aggregations = aggregations_from_datastore_query("Query", :widget_aggregations, <<~QUERY)
              query {
                widget_aggregations {
                  #{before_nodes}
                    values1: aggregated_values {
                      amount_cents {
                        approximate_avg
                      }
                    }

                    values2: aggregated_values {
                      amount_cents {
                        approximate_avg
                      }
                    }

                    values3: aggregated_values {
                      amount_cents {
                        exact_sum
                      }
                    }
                  #{after_nodes}
                }
              }
            QUERY

            expect(aggregations).to eq([aggregation_query_of(
              name: "widget_aggregations",
              computations: [
                computation_of("amount_cents", :avg, computed_field_name: "approximate_avg"),
                computation_of("amount_cents", :sum, computed_field_name: "exact_sum")
              ]
            )])
          end

          it "supports multiple aliases on subfields of `aggregated_values` since that doesn't interfere with grouping" do
            aggregations = aggregations_from_datastore_query("Query", :widget_aggregations, <<~QUERY)
              query {
                widget_aggregations {
                  #{before_nodes}
                    aggregated_values {
                      ac1: amount_cents {
                        approximate_avg
                      }

                      ac2: amount_cents {
                        aa1: approximate_avg
                        aa2: approximate_avg
                        exact_sum
                      }
                    }
                  #{after_nodes}
                }
              }
            QUERY

            expect(aggregations).to eq([aggregation_query_of(
              name: "widget_aggregations",
              computations: [
                computation_of("amount_cents", :avg, computed_field_name: "approximate_avg", field_names_in_graphql_query: ["ac1"]),
                computation_of("amount_cents", :avg, computed_field_name: "approximate_avg", field_names_in_graphql_query: ["ac2"]),
                computation_of("amount_cents", :sum, computed_field_name: "exact_sum", field_names_in_graphql_query: ["ac2"])
              ]
            )])
          end

          it "supports multiple aliases on subfields of `grouped_by` since that doesn't interfere with grouping" do
            aggregations = aggregations_from_datastore_query("Query", :widget_aggregations, <<~QUERY)
              query {
                widget_aggregations {
                  #{before_nodes}
                    count

                    grouped_by {
                      size1: size
                      size2: size
                      color
                    }
                  #{after_nodes}
                }
              }
            QUERY

            expect(aggregations).to eq([aggregation_query_of(
              name: "widget_aggregations",
              needs_doc_count: true,
              groupings: [
                field_term_grouping_of("size", field_names_in_graphql_query: ["size1"]),
                field_term_grouping_of("size", field_names_in_graphql_query: ["size2"]),
                field_term_grouping_of("color")
              ]
            )])
          end

          it "can build an aggregations object with multiple computations and groupings (including on a nested scalar field)" do
            aggregations = aggregations_from_datastore_query("Query", :widget_aggregations, <<~QUERY)
              query {
                widget_aggregations {
                  #{before_nodes}
                    grouped_by {
                      size
                      created_at {
                        as_date_time(truncation_unit: YEAR)
                      }
                      cost {
                        currency
                      }
                    }

                    aggregated_values {
                      amount_cents {
                        exact_max
                      }

                      cost {
                        amount_cents {
                          exact_max
                          approximate_avg
                        }
                      }
                    }
                  #{after_nodes}
                }
              }
            QUERY

            expect(aggregations).to eq([aggregation_query_of(
              name: "widget_aggregations",
              computations: [
                computation_of("amount_cents", :max, computed_field_name: "exact_max"),
                computation_of("cost", "amount_cents", :max, computed_field_name: "exact_max"),
                computation_of("cost", "amount_cents", :avg, computed_field_name: "approximate_avg")
              ],
              groupings: [
                field_term_grouping_of("size"),
                field_term_grouping_of("cost", "currency"),
                date_histogram_grouping_of("created_at", "year", graphql_subfield: "as_date_time")
              ]
            )])
          end

          it "only builds aggregations for relay connection fields with an aggregations subfield, even when the same field name is used elsewhere" do
            fields = fields_with_aggregations_for(<<~QUERY)
              query {
                widget_aggregations {
                  #{before_nodes}
                    grouped_by {
                      size
                      color
                      created_at {
                        as_date_time(truncation_unit: DAY)
                      }
                    }

                    aggregated_values {
                      amount_cents {
                        approximate_avg
                        exact_max
                      }
                    }
                  #{after_nodes}
                }

                components {
                  #{before_nodes}
                    widgets {
                      edges {
                        node {
                          id
                        }
                      }
                    }
                  #{after_nodes}
                }
              }
            QUERY

            expect(fields).to eq ["Query.widget_aggregations"]
          end

          it "does not build any groupings or computations for the aggregation `count` field" do
            aggregations = aggregations_from_datastore_query("Query", :widget_aggregations, <<~QUERY)
              query {
                widget_aggregations {
                  #{before_nodes}
                    count
                  #{after_nodes}
                }
              }
            QUERY

            expect(aggregations).to eq([aggregation_query_of(name: "widget_aggregations", computations: [], groupings: [], needs_doc_count: true)])
          end

          it "supports aliases for aggregated_values, grouped_by, and count" do
            aggregations = aggregations_from_datastore_query("Query", :widget_aggregations, <<~QUERY)
              query {
                widget_aggregations {
                  #{before_nodes}
                    the_grouped_by: grouped_by {
                      size
                    }

                    the_count: count

                    the_aggregated_values: aggregated_values {
                      amount_cents {
                        approximate_avg
                      }
                    }
                  #{after_nodes}
                }
              }
            QUERY

            expect(aggregations).to eq([aggregation_query_of(
              name: "widget_aggregations",
              computations: [
                computation_of("amount_cents", :avg, computed_field_name: "approximate_avg")
              ],
              needs_doc_count: true,
              groupings: [
                field_term_grouping_of("size")
              ]
            )])
          end

          describe "needs_doc_count" do
            it "is true when the count field is requested" do
              aggs = aggregations_from_datastore_query("Query", :widget_aggregations, <<~QUERY).first
                query {
                  widget_aggregations {
                    #{before_nodes}
                      count

                      aggregated_values {
                        amount_cents {
                          approximate_avg
                          exact_max
                        }
                      }
                    #{after_nodes}
                  }
                }
              QUERY

              expect(aggs.needs_doc_count).to be true
            end

            it "is false when the count field is not requested" do
              aggs = aggregations_from_datastore_query("Query", :widget_aggregations, <<~QUERY).first
                query {
                  widget_aggregations {
                    #{before_nodes}
                      aggregated_values {
                        amount_cents {
                          approximate_avg
                          exact_max
                        }
                      }
                    #{after_nodes}
                  }
                }
              QUERY

              expect(aggs.needs_doc_count).to be false
            end
          end
        end

        it "works correctly when nothing under `node` is requested (e.g. just `page_info`)" do
          aggregations = aggregations_from_datastore_query("Query", :widget_aggregations, <<~QUERY)
            query {
              widget_aggregations {
                page_info {
                  has_next_page
                  end_cursor
                }
              }
            }
          QUERY

          expect(aggregations).to eq([aggregation_query_of(
            name: "widget_aggregations",
            needs_doc_count: false
          )])
        end

        context "when the query uses `edges { node { ... } }`" do
          include_examples "a query selecting nodes under aggregations",
            before_nodes: "edges { node {",
            after_nodes: "} }"

          it "does not support multiple unaliased `edges` because if different `grouped_by` fields are selected under `node` we can have conflicting grouping requirements" do
            error = single_graphql_error_for(<<~QUERY)
              query {
                widget_aggregations {
                  edges {
                    node {
                      grouped_by { size }
                      count
                    }
                  }

                  edges {
                    node {
                      grouped_by { color }
                      count
                    }
                  }
                }
              }
            QUERY

            expect(error["message"]).to include("more than one `edges` selection under `widget_aggregations` (`edges`, `edges`),")
          end

          it "does not support multiple aliases on `edges` because if different `grouped_by` fields are selected under `node` we can have conflicting grouping requirements" do
            error = single_graphql_error_for(<<~QUERY)
              query {
                widget_aggregations {
                  by_size: edges {
                    node {
                      grouped_by { size }
                      count
                    }
                  }

                  by_color: edges {
                    node {
                      grouped_by { color }
                      count
                    }
                  }
                }
              }
            QUERY

            expect(error["message"]).to include("more than one `edges` selection under `widget_aggregations` (`by_size`, `by_color`),")
          end

          it "does not support multiple aliases on `node` because if different `grouped_by` fields are selected we can have conflicting grouping requirements" do
            error = single_graphql_error_for(<<~QUERY)
              query {
                widget_aggregations {
                  edges {
                    by_size: node {
                      grouped_by { size }
                      count
                    }

                    node {
                      grouped_by { color }
                      count
                    }
                  }
                }
              }
            QUERY

            expect(error["message"]).to include("more than one `node` selection under `widget_aggregations` (`by_size`, `node`),")
          end

          it "does not support multiple unaliased `node`s because if different `grouped_by` fields are selected we can have conflicting grouping requirements" do
            error = single_graphql_error_for(<<~QUERY)
              query {
                widget_aggregations {
                  edges {
                    node {
                      grouped_by { size }
                      count
                    }

                    node {
                      grouped_by { color }
                      count
                    }
                  }
                }
              }
            QUERY

            expect(error["message"]).to include("more than one `node` selection under `widget_aggregations` (`node`, `node`),")
          end

          it "supports a single alias on every layer of nesting of a full query, since that doesn't interfere with grouping" do
            aggregations = aggregations_from_datastore_query("Query", :wa, <<~QUERY)
              query {
                wa: widget_aggregations {
                  e: edges {
                    n: node {
                      g: grouped_by {
                        s: size
                        c: color
                      }

                      c: count

                      av: aggregated_values {
                        ac: amount_cents {
                          aa: approximate_avg
                          em: exact_max
                        }
                      }
                    }
                  }
                }
              }
            QUERY

            expect(aggregations).to eq([aggregation_query_of(
              name: "wa",
              computations: [
                computation_of("amount_cents", :avg, computed_field_name: "approximate_avg", field_names_in_graphql_query: ["ac"]),
                computation_of("amount_cents", :max, computed_field_name: "exact_max", field_names_in_graphql_query: ["ac"])
              ],
              groupings: [
                field_term_grouping_of("size", field_names_in_graphql_query: ["s"]),
                field_term_grouping_of("color", field_names_in_graphql_query: ["c"])
              ],
              needs_doc_count: true
            )])
          end
        end

        context "when the query uses `nodes { }` and `edges { node { } }`" do
          it "returns an error to guard against conflicting grouping requirements" do
            error = single_graphql_error_for(<<~QUERY)
              query {
                widget_aggregations {
                  nodes {
                    grouped_by { size }
                    count
                  }

                  edges {
                    node {
                      grouped_by { color }
                      count
                    }
                  }
                }
              }
            QUERY

            expect(error["message"]).to include("more than one node selection (`nodes`, `edges.node`)")
          end
        end

        context "when the query uses `nodes { }`" do
          include_examples "a query selecting nodes under aggregations",
            before_nodes: "nodes {",
            after_nodes: "}"

          it "does not support multiple unaliased `nodes` because if different `grouped_by` fields are selected under `node` we can have conflicting grouping requirements" do
            error = single_graphql_error_for(<<~QUERY)
              query {
                widget_aggregations {
                  nodes {
                    grouped_by { size }
                    count
                  }

                  nodes {
                    grouped_by { color }
                    count
                  }
                }
              }
            QUERY

            expect(error["message"]).to include("more than one `nodes` selection under `widget_aggregations` (`nodes`, `nodes`),")
          end

          it "does not support multiple aliases on `nodes` because if different `grouped_by` fields are selected we can have conflicting grouping requirements" do
            error = single_graphql_error_for(<<~QUERY)
              query {
                widget_aggregations {
                  by_size: nodes {
                    grouped_by { size }
                    count
                  }

                  by_color: nodes {
                    grouped_by { color }
                    count
                  }
                }
              }
            QUERY

            expect(error["message"]).to include("more than one `nodes` selection under `widget_aggregations` (`by_size`, `by_color`),")
          end

          it "supports a single alias on every layer of nesting of a full query, since that doesn't interfere with grouping" do
            aggregations = aggregations_from_datastore_query("Query", :wa, <<~QUERY)
              query {
                wa: widget_aggregations {
                  n: nodes {
                    g: grouped_by {
                      s: size
                      c: color
                    }

                    c: count

                    av: aggregated_values {
                      ac: amount_cents {
                        aa: approximate_avg
                        em: exact_max
                      }
                    }
                  }
                }
              }
            QUERY

            expect(aggregations).to eq([aggregation_query_of(
              name: "wa",
              computations: [
                computation_of("amount_cents", :avg, computed_field_name: "approximate_avg", field_names_in_graphql_query: ["ac"]),
                computation_of("amount_cents", :max, computed_field_name: "exact_max", field_names_in_graphql_query: ["ac"])
              ],
              groupings: [
                field_term_grouping_of("size", field_names_in_graphql_query: ["s"]),
                field_term_grouping_of("color", field_names_in_graphql_query: ["c"])
              ],
              needs_doc_count: true
            )])
          end
        end

        def aggregations_from_datastore_query(type, field, graphql_query, **graphql_opts)
          datastore_query_for(
            schema_artifacts: schema_artifacts,
            graphql_query: graphql_query,
            type: type,
            field: field,
            **graphql_opts
          ).aggregations.values
        end

        def aggregations_by_field_name_for(query_string)
          queries = datastore_queries_by_field_for(query_string, schema_artifacts: schema_artifacts)

          queries.filter_map do |field, field_queries|
            expect(field_queries.size).to eq(1)
            field_query = field_queries.first

            if field_query.aggregations.any?
              expect(field_query.aggregations.size).to eq(1)
              [field, field_query.aggregations.values.first]
            end
          end.to_h
        end

        def fields_with_aggregations_for(query_string)
          aggregations_by_field_name_for(query_string).keys
        end

        def graphql_errors_for(query_string, **graphql_opts)
          super(schema_artifacts: schema_artifacts, graphql_query: query_string, **graphql_opts)
        end

        def single_graphql_error_for(query_string)
          errors = graphql_errors_for(query_string)
          expect(errors.size).to eq 1
          errors.first
        end

        def define_schema(schema, amount_cents_opts: {}, cost_opts: {}, legacy_grouping_schema: false)
          schema.object_type "Money" do |t|
            t.field "currency", "String!"
            t.field "amount_cents", "Int!"
            t.field "amount", "Int", name_in_index: "amount_in_index"
          end

          schema.object_type "Widget" do |t|
            t.field "id", "ID"
            t.field "name", "String"
            t.field "created_at", "DateTime", legacy_grouping_schema: legacy_grouping_schema
            t.field "created_on", "Date", legacy_grouping_schema: legacy_grouping_schema
            t.field "size", "String"
            t.field "color", "String"
            t.field "amount_cents", "Int", **amount_cents_opts
            t.field "cost", "Money", **cost_opts
            t.field "costs", "[Money!]!" do |f|
              f.mapping type: "nested"
            end
            t.field "component_ids", "[ID!]!"

            t.index "widgets"
          end

          schema.object_type "Component" do |t|
            t.field "id", "ID!"
            t.field "name", "String!"
            t.relates_to_many "widgets", "Widget", via: "component_ids", dir: :in, singular: "widget"
            t.index "components"
          end
        end

        def sub_fields_of(type_name)
          ::GraphQL::Schema
            .from_definition(schema_artifacts.graphql_schema_string)
            .types
            .fetch(type_name)
            .fields
            .keys
        end

        def as_day_of_week_grouping_of(*field_names_in_index, **args)
          super(*field_names_in_index, runtime_metadata: schema_artifacts.runtime_metadata, **args)
        end

        def as_time_of_day_grouping_of(*field_names_in_index, interval, **args)
          super(*field_names_in_index, interval, runtime_metadata: schema_artifacts.runtime_metadata, **args)
        end
      end
    end
  end
end
