# Copyright 2024 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require_relative "datastore_aggregation_query_integration_support"
require "support/sub_aggregation_support"
require "time"

module ElasticGraph
  class GraphQL
    RSpec.describe DatastoreQuery, "sub-aggregations" do
      using Aggregation::SubAggregationRefinements
      include_context "DatastoreAggregationQueryIntegrationSupport"
      include_context "sub-aggregation support", Aggregation::NonCompositeGroupingAdapter

      before do
        index_into(
          graphql,
          build(
            :team,
            current_players: [build(:player, name: "Bob", seasons: [
              build(:player_season, year: 2020),
              build(:player_season, year: 2021)
            ])],
            seasons: [
              build(:team_season, year: 2022, record: build(:team_record, wins: 50), notes: ["new rules"], players: [
                build(:player, seasons: [build(:player_season, year: 2015), build(:player_season, year: 2016)]),
                build(:player, seasons: [build(:player_season, year: 2015)])
              ])
            ]
          ),
          build(
            :team,
            current_players: [build(:player, name: "Tom", seasons: []), build(:player, name: "Ted", seasons: [])],
            seasons: []
          ),
          build(
            :team,
            current_players: [build(:player, name: "Dan", seasons: []), build(:player, name: "Ben", seasons: [])],
            seasons: [
              build(:team_season, year: 2022, record: build(:team_record, wins: 40), notes: ["new rules"], players: []),
              build(:team_season, year: 2021, record: build(:team_record, wins: 60), notes: ["old rules"], players: []),
              build(:team_season, year: 2020, record: build(:team_record, wins: 30), notes: ["old rules", "pandemic"], players: [])
            ]
          ),
          build(
            :team,
            current_players: [],
            seasons: []
          )
        )
      end

      it "supports multiple sibling sub-aggregations" do
        query = aggregation_query_of(name: "teams", sub_aggregations: [
          nested_sub_aggregation_of(path_in_index: ["current_players_nested"], query: sub_aggregation_query_of(name: "current_players_nested", first: 12)),
          nested_sub_aggregation_of(path_in_index: ["seasons_nested"], query: sub_aggregation_query_of(name: "seasons_nested", first: 5))
        ])

        results = search_datastore_aggregations(query, index_def_name: "teams")

        expect(results).to eq [{
          "doc_count" => 0,
          "key" => {},
          "teams:current_players_nested" => {"doc_count" => 5, "meta" => outer_meta(size: 12)},
          "teams:seasons_nested" => {"doc_count" => 4, "meta" => outer_meta(size: 5)}
        }]
      end

      it "returns a well-structured response even when filtering to no shard routing values", :expect_search_routing do
        query = aggregation_query_of(name: "teams", sub_aggregations: [
          nested_sub_aggregation_of(path_in_index: ["current_players_nested"], query: sub_aggregation_query_of(name: "current_players_nested", first: 12)),
          nested_sub_aggregation_of(path_in_index: ["seasons_nested"], query: sub_aggregation_query_of(name: "seasons_nested", first: 5))
        ])

        results = search_datastore_aggregations(query, index_def_name: "teams", filter: {"league" => {"equal_to_any_of" => []}})

        expect(results).to eq [{
          "doc_count" => 0,
          "key" => {},
          "teams:current_players_nested" => {"doc_count" => 0, "meta" => outer_meta(size: 12)},
          "teams:seasons_nested" => {"doc_count" => 0, "meta" => outer_meta(size: 5)}
        }]
      end

      it "returns a well-structured response even when filtering on the rollover field to an empty set of values", :expect_index_exclusions do
        query = aggregation_query_of(name: "teams", sub_aggregations: [
          nested_sub_aggregation_of(path_in_index: ["current_players_nested"], query: sub_aggregation_query_of(name: "current_players_nested", first: 12)),
          nested_sub_aggregation_of(path_in_index: ["seasons_nested"], query: sub_aggregation_query_of(name: "seasons_nested", first: 5))
        ])

        results = search_datastore_aggregations(query, index_def_name: "teams", filter: {"formed_on" => {"equal_to_any_of" => []}})

        expect(results).to eq [{
          "doc_count" => 0,
          "key" => {},
          "teams:current_players_nested" => {"doc_count" => 0, "meta" => outer_meta(size: 12)},
          "teams:seasons_nested" => {"doc_count" => 0, "meta" => outer_meta(size: 5)}
        }]
      end

      it "returns a well-structured response even when filtering on the rollover field with criteria that excludes all existing indices", :expect_index_exclusions do
        query = aggregation_query_of(name: "teams", sub_aggregations: [
          nested_sub_aggregation_of(path_in_index: ["current_players_nested"], query: sub_aggregation_query_of(name: "current_players_nested", first: 12)),
          nested_sub_aggregation_of(path_in_index: ["seasons_nested"], query: sub_aggregation_query_of(name: "seasons_nested", first: 5))
        ])

        results = search_datastore_aggregations(query, index_def_name: "teams", filter: {"formed_on" => {"gt" => "7890-01-01"}})

        expect(results).to eq [{
          "doc_count" => 0,
          "key" => {},
          "teams:current_players_nested" => {"doc_count" => 0, "meta" => outer_meta(size: 12)},
          "teams:seasons_nested" => {"doc_count" => 0, "meta" => outer_meta(size: 5)}
        }]
      end

      it "supports sub-aggregations of sub-aggregations of sub-aggregations" do
        query = aggregation_query_of(name: "teams", sub_aggregations: [
          nested_sub_aggregation_of(path_in_index: ["seasons_nested"], query: sub_aggregation_query_of(
            name: "seasons_nested",
            first: 15,
            sub_aggregations: [
              nested_sub_aggregation_of(path_in_index: ["seasons_nested", "players_nested"], query: sub_aggregation_query_of(
                name: "players_nested",
                first: 16,
                sub_aggregations: [
                  nested_sub_aggregation_of(path_in_index: ["seasons_nested", "players_nested", "seasons_nested"], query: sub_aggregation_query_of(
                    name: "seasons_nested",
                    first: 17
                  ))
                ]
              ))
            ]
          ))
        ])

        results = search_datastore_aggregations(query, index_def_name: "teams")

        expect(results).to eq [{
          "doc_count" => 0,
          "key" => {},
          "teams:seasons_nested" => {
            "doc_count" => 4,
            "meta" => outer_meta(size: 15),
            "teams:seasons_nested:seasons_nested.players_nested" => {
              "doc_count" => 2,
              "meta" => outer_meta(size: 16),
              "teams:seasons_nested:players_nested:seasons_nested.players_nested.seasons_nested" => {
                "doc_count" => 3,
                "meta" => outer_meta(size: 17)
              }
            }
          }
        }]
      end

      it "supports nesting sub-aggreations under an extra object layer" do
        query = aggregation_query_of(name: "teams", sub_aggregations: [
          nested_sub_aggregation_of(path_in_index: ["the_nested_fields", "current_players"], query: sub_aggregation_query_of(name: "current_players"))
        ])

        results = search_datastore_aggregations(query, index_def_name: "teams")

        expect(results).to eq [{
          "doc_count" => 0,
          "key" => {},
          "teams:the_nested_fields.current_players" => {"doc_count" => 5, "meta" => outer_meta}
        }]
      end

      it "supports filtered sub-aggregations" do
        query = aggregation_query_of(name: "teams", sub_aggregations: [
          nested_sub_aggregation_of(path_in_index: ["current_players_nested"], query: sub_aggregation_query_of(name: "current_players_nested", filter: {
            "name" => {"equal_to_any_of" => %w[Dan Ted Bob]}
          }))
        ])

        results = search_datastore_aggregations(query, index_def_name: "teams")

        expect(results).to eq [{
          "doc_count" => 0,
          "key" => {},
          "teams:current_players_nested" => {
            "meta" => outer_meta({"bucket_path" => ["current_players_nested:filtered"]}),
            "doc_count" => 5,
            "current_players_nested:filtered" => {"doc_count" => 3}
          }
        }]
      end

      it "treats empty filters as `true`" do
        query = aggregation_query_of(name: "teams", sub_aggregations: [
          nested_sub_aggregation_of(path_in_index: ["current_players_nested"], query: sub_aggregation_query_of(name: "current_players_nested", filter: {
            "name" => {"equal_to_any_of" => nil}
          }))
        ])

        results = search_datastore_aggregations(query, index_def_name: "teams")

        expect(results).to eq [{
          "doc_count" => 0,
          "key" => {},
          "teams:current_players_nested" => {"doc_count" => 5, "meta" => outer_meta}
        }]
      end

      it "supports sub-aggregations under a filtered sub-aggregation" do
        query = aggregation_query_of(name: "teams", sub_aggregations: [
          nested_sub_aggregation_of(path_in_index: ["current_players_nested"], query: sub_aggregation_query_of(
            name: "current_players_nested",
            filter: {"name" => {"equal_to_any_of" => %w[Dan Ted Bob]}},
            sub_aggregations: [nested_sub_aggregation_of(
              path_in_index: ["current_players_nested", "seasons_nested"],
              query: sub_aggregation_query_of(name: "seasons_nested")
            )]
          ))
        ])

        results = search_datastore_aggregations(query, index_def_name: "teams")

        expect(results).to eq [{
          "doc_count" => 0,
          "key" => {},
          "teams:current_players_nested" => {
            "meta" => outer_meta({"bucket_path" => ["current_players_nested:filtered"]}),
            "doc_count" => 5,
            "current_players_nested:filtered" => {
              "doc_count" => 3,
              "teams:current_players_nested:current_players_nested.seasons_nested" => {"doc_count" => 2, "meta" => outer_meta}
            }
          }
        }]
      end

      it "supports filtered sub-aggregations under a filtered sub-aggregation" do
        query = aggregation_query_of(name: "teams", sub_aggregations: [
          nested_sub_aggregation_of(path_in_index: ["current_players_nested"], query: sub_aggregation_query_of(
            name: "current_players_nested",
            filter: {"name" => {"equal_to_any_of" => %w[Dan Ted Bob]}},
            sub_aggregations: [nested_sub_aggregation_of(
              path_in_index: ["current_players_nested", "seasons_nested"],
              query: sub_aggregation_query_of(name: "seasons_nested", filter: {"year" => {"gt" => 2020}})
            )]
          ))
        ])

        results = search_datastore_aggregations(query, index_def_name: "teams")

        expect(results).to eq [{
          "doc_count" => 0,
          "key" => {},
          "teams:current_players_nested" => {
            "meta" => outer_meta({"bucket_path" => ["current_players_nested:filtered"]}),
            "doc_count" => 5,
            "current_players_nested:filtered" => {
              "doc_count" => 3,
              "teams:current_players_nested:current_players_nested.seasons_nested" => {
                "meta" => outer_meta({"bucket_path" => ["seasons_nested:filtered"]}),
                "doc_count" => 2,
                "seasons_nested:filtered" => {"doc_count" => 1}
              }
            }
          }
        }]
      end

      context "with computations" do
        it "can compute ungrouped aggregated values" do
          query = aggregation_query_of(name: "teams", sub_aggregations: [
            nested_sub_aggregation_of(path_in_index: ["seasons_nested"], query: sub_aggregation_query_of(name: "seasons_nested", computations: [
              computation_of("seasons_nested", "year", :min, computed_field_name: "exact_min"),
              computation_of("seasons_nested", "the_record", "win_count", :max, computed_field_name: "exact_max"),
              computation_of("seasons_nested", "the_record", "win_count", :avg, computed_field_name: "approximate_avg")
            ]))
          ])

          results = search_datastore_aggregations(query, index_def_name: "teams")

          expect(results).to eq [{
            "doc_count" => 0,
            "key" => {},
            "teams:seasons_nested" => {
              "doc_count" => 4,
              "meta" => outer_meta,
              "seasons_nested:seasons_nested.the_record.win_count:approximate_avg" => {"value" => 45},
              "seasons_nested:seasons_nested.the_record.win_count:exact_max" => {"value" => 60.0},
              "seasons_nested:seasons_nested.year:exact_min" => {"value" => 2020.0}
            }
          }]
        end

        it "can compute filtered aggregated values" do
          query = aggregation_query_of(name: "teams", sub_aggregations: [
            nested_sub_aggregation_of(path_in_index: ["seasons_nested"], query: sub_aggregation_query_of(
              name: "seasons_nested",
              filter: {"year" => {"gt" => 2021}},
              computations: [
                computation_of("seasons_nested", "year", :min, computed_field_name: "exact_min"),
                computation_of("seasons_nested", "the_record", "win_count", :max, computed_field_name: "exact_max"),
                computation_of("seasons_nested", "the_record", "win_count", :avg, computed_field_name: "approximate_avg")
              ]
            ))
          ])

          results = search_datastore_aggregations(query, index_def_name: "teams")

          expect(results).to eq [{
            "doc_count" => 0,
            "key" => {},
            "teams:seasons_nested" => {
              "doc_count" => 4,
              "meta" => outer_meta({"bucket_path" => ["seasons_nested:filtered"]}),
              "seasons_nested:filtered" => {
                "doc_count" => 2,
                "seasons_nested:seasons_nested.the_record.win_count:approximate_avg" => {"value" => 45},
                "seasons_nested:seasons_nested.the_record.win_count:exact_max" => {"value" => 50.0},
                "seasons_nested:seasons_nested.year:exact_min" => {"value" => 2022.0}
              }
            }
          }]
        end

        it "can compute grouped aggregated values" do
          query = aggregation_query_of(name: "teams", sub_aggregations: [
            nested_sub_aggregation_of(path_in_index: ["seasons_nested"], query: sub_aggregation_query_of(
              name: "seasons_nested",
              computations: [
                computation_of("seasons_nested", "year", :min, computed_field_name: "exact_min"),
                computation_of("seasons_nested", "the_record", "win_count", :max, computed_field_name: "exact_max"),
                computation_of("seasons_nested", "the_record", "win_count", :avg, computed_field_name: "approximate_avg")
              ],
              groupings: [
                field_term_grouping_of("seasons_nested", "notes")
              ]
            ))
          ])

          results = search_datastore_aggregations(query, index_def_name: "teams")

          expect(results).to eq [{
            "doc_count" => 0,
            "key" => {},
            "teams:seasons_nested" => {
              "meta" => outer_meta({"buckets_path" => ["seasons_nested.notes"]}),
              "doc_count" => 4,
              "seasons_nested.notes" => {
                "meta" => inner_terms_meta({"key_path" => ["key"], "grouping_fields" => ["seasons_nested.notes"]}),
                "doc_count_error_upper_bound" => 0,
                "sum_other_doc_count" => 0,
                "buckets" => [
                  term_bucket("new rules", 2, {
                    "seasons_nested:seasons_nested.year:exact_min" => {"value" => 2022.0},
                    "seasons_nested:seasons_nested.the_record.win_count:exact_max" => {"value" => 50.0},
                    "seasons_nested:seasons_nested.the_record.win_count:approximate_avg" => {"value" => 45.0}
                  }),
                  term_bucket("old rules", 2, {
                    "seasons_nested:seasons_nested.year:exact_min" => {"value" => 2020.0},
                    "seasons_nested:seasons_nested.the_record.win_count:exact_max" => {"value" => 60.0},
                    "seasons_nested:seasons_nested.the_record.win_count:approximate_avg" => {"value" => 45.0}
                  }),
                  term_bucket("pandemic", 1, {
                    "seasons_nested:seasons_nested.year:exact_min" => {"value" => 2020.0},
                    "seasons_nested:seasons_nested.the_record.win_count:exact_max" => {"value" => 30.0},
                    "seasons_nested:seasons_nested.the_record.win_count:approximate_avg" => {"value" => 30.0}
                  })
                ]
              }
            }.with_missing_value_bucket(0, {
              "seasons_nested:seasons_nested.year:exact_min" => {"value" => nil},
              "seasons_nested:seasons_nested.the_record.win_count:exact_max" => {"value" => nil},
              "seasons_nested:seasons_nested.the_record.win_count:approximate_avg" => {"value" => nil}
            })
          }]
        end

        it "can compute aggregated values on multiple levels of sub-aggregations" do
          query = aggregation_query_of(name: "teams", sub_aggregations: [
            nested_sub_aggregation_of(path_in_index: ["seasons_nested"], query: sub_aggregation_query_of(
              name: "seasons_nested",
              computations: [computation_of("seasons_nested", "year", :min)],
              sub_aggregations: [nested_sub_aggregation_of(path_in_index: ["seasons_nested", "players_nested"], query: sub_aggregation_query_of(
                name: "players_nested",
                computations: [computation_of("seasons_nested", "players_nested", "name", :cardinality)],
                sub_aggregations: [nested_sub_aggregation_of(path_in_index: ["seasons_nested", "players_nested", "seasons_nested"], query: sub_aggregation_query_of(
                  name: "seasons_nested",
                  computations: [computation_of("seasons_nested", "players_nested", "seasons_nested", "year", :max)]
                ))]
              ))]
            ))
          ])

          results = search_datastore_aggregations(query, index_def_name: "teams")

          expect(results).to eq [{
            "doc_count" => 0,
            "key" => {},
            "teams:seasons_nested" => {
              "doc_count" => 4,
              "meta" => outer_meta,
              "seasons_nested:seasons_nested.year:min" => {"value" => 2020.0},
              "teams:seasons_nested:seasons_nested.players_nested" => {
                "doc_count" => 2,
                "meta" => outer_meta,
                "players_nested:seasons_nested.players_nested.name:cardinality" => {"value" => 2},
                "teams:seasons_nested:players_nested:seasons_nested.players_nested.seasons_nested" => {
                  "doc_count" => 3,
                  "meta" => outer_meta,
                  "seasons_nested:seasons_nested.players_nested.seasons_nested.year:max" => {"value" => 2016.0}
                }
              }
            }
          }]
        end
      end

      context "with groupings (using the `NonCompositeGroupingAdapter`)" do
        include_context "sub-aggregation support", Aggregation::NonCompositeGroupingAdapter

        it "can group sub-aggregations on a single non-date field" do
          query = aggregation_query_of(name: "teams", sub_aggregations: [
            nested_sub_aggregation_of(path_in_index: ["seasons_nested"], query: sub_aggregation_query_of(name: "seasons_nested", groupings: [
              field_term_grouping_of("seasons_nested", "year")
            ]))
          ])

          results = search_datastore_aggregations(query, index_def_name: "teams")

          expect(results).to eq([{
            "doc_count" => 0,
            "key" => {},
            "teams:seasons_nested" => {
              "doc_count" => 4,
              "meta" => outer_meta({"buckets_path" => ["seasons_nested.year"]}),
              "seasons_nested.year" => {
                "meta" => inner_terms_meta({"grouping_fields" => ["seasons_nested.year"], "key_path" => ["key"]}),
                "buckets" => [
                  term_bucket(2022, 2),
                  term_bucket(2020, 1),
                  term_bucket(2021, 1)
                ],
                "doc_count_error_upper_bound" => 0,
                "sum_other_doc_count" => 0
              }
            }.with_missing_value_bucket(0)
          }])
        end

        it "can group sub-aggregations on multiple non-date fields" do
          query = aggregation_query_of(name: "teams", sub_aggregations: [
            nested_sub_aggregation_of(path_in_index: ["seasons_nested"], query: sub_aggregation_query_of(name: "seasons_nested", groupings: [
              field_term_grouping_of("seasons_nested", "year"),
              field_term_grouping_of("seasons_nested", "notes")
            ]))
          ])

          results = search_datastore_aggregations(query, index_def_name: "teams")

          expect(results).to eq([{
            "doc_count" => 0,
            "key" => {},
            "teams:seasons_nested" => {
              "doc_count" => 4,
              "meta" => outer_meta({"buckets_path" => ["seasons_nested.year"]}),
              "seasons_nested.year" => {
                "meta" => inner_terms_meta({
                  "buckets_path" => ["seasons_nested.notes"],
                  "key_path" => ["key"],
                  "grouping_fields" => ["seasons_nested.year"]
                }),
                "doc_count_error_upper_bound" => 0,
                "sum_other_doc_count" => 0,
                "buckets" => [
                  term_bucket(2022, 2, {"seasons_nested.notes" => {
                    "meta" => inner_terms_meta({"key_path" => ["key"], "grouping_fields" => ["seasons_nested.notes"]}),
                    "doc_count_error_upper_bound" => 0,
                    "sum_other_doc_count" => 0,
                    "buckets" => [term_bucket("new rules", 2)]
                  }}.with_missing_value_bucket(0)),
                  term_bucket(2020, 1, {"seasons_nested.notes" => {
                    "meta" => inner_terms_meta({"key_path" => ["key"], "grouping_fields" => ["seasons_nested.notes"]}),
                    "doc_count_error_upper_bound" => 0,
                    "sum_other_doc_count" => 0,
                    "buckets" => [term_bucket("old rules", 1), term_bucket("pandemic", 1)]
                  }}.with_missing_value_bucket(0)),
                  term_bucket(2021, 1, {"seasons_nested.notes" => {
                    "meta" => inner_terms_meta({"key_path" => ["key"], "grouping_fields" => ["seasons_nested.notes"]}),
                    "doc_count_error_upper_bound" => 0,
                    "sum_other_doc_count" => 0,
                    "buckets" => [term_bucket("old rules", 1)]
                  }}.with_missing_value_bucket(0))
                ]
              }
            }.with_missing_value_bucket(0, {
              "seasons_nested.notes" => {
                "meta" => inner_terms_meta({"key_path" => ["key"], "grouping_fields" => ["seasons_nested.notes"]}),
                "doc_count_error_upper_bound" => 0,
                "sum_other_doc_count" => 0,
                "buckets" => []
              }
            }.with_missing_value_bucket(0))
          }])
        end

        it "limits the size of `terms` grouping based on the sub-aggregation `size`" do
          query = aggregation_query_of(name: "teams", sub_aggregations: [
            nested_sub_aggregation_of(path_in_index: ["seasons_nested"], query: sub_aggregation_query_of(
              name: "seasons_nested",
              first: 1,
              groupings: [field_term_grouping_of("seasons_nested", "year")]
            ))
          ])

          results = search_datastore_aggregations(query, index_def_name: "teams")

          expect(results).to eq([{
            "doc_count" => 0,
            "key" => {},
            "teams:seasons_nested" => {
              "doc_count" => 4,
              "meta" => outer_meta({"buckets_path" => ["seasons_nested.year"]}, size: 1),
              "seasons_nested.year" => {
                "meta" => inner_terms_meta({"grouping_fields" => ["seasons_nested.year"], "key_path" => ["key"]}),
                "buckets" => [term_bucket(2022, 2)],
                "doc_count_error_upper_bound" => 0,
                "sum_other_doc_count" => 2
              }
            }.with_missing_value_bucket(0)
          }])
        end

        it "limits the size of a `terms` grouping based on the sub-aggregation `size`" do
          query = aggregation_query_of(name: "teams", sub_aggregations: [
            nested_sub_aggregation_of(path_in_index: ["seasons_nested"], query: sub_aggregation_query_of(
              name: "seasons_nested",
              first: 1,
              groupings: [field_term_grouping_of("seasons_nested", "year"), field_term_grouping_of("seasons_nested", "notes")]
            ))
          ])

          results = search_datastore_aggregations(query, index_def_name: "teams")

          expect(results).to eq([{
            "doc_count" => 0,
            "key" => {},
            "teams:seasons_nested" => {
              "doc_count" => 4,
              "meta" => outer_meta({"buckets_path" => ["seasons_nested.year"]}, size: 1),
              "seasons_nested.year" => {
                "meta" => inner_terms_meta({"buckets_path" => ["seasons_nested.notes"], "grouping_fields" => ["seasons_nested.year"], "key_path" => ["key"]}),
                "buckets" => [
                  term_bucket(2022, 2, {
                    "seasons_nested.notes" => {
                      "meta" => inner_terms_meta({"grouping_fields" => ["seasons_nested.notes"], "key_path" => ["key"]}),
                      "buckets" => [
                        term_bucket("new rules", 2)
                      ],
                      "doc_count_error_upper_bound" => 0,
                      "sum_other_doc_count" => 0
                    }
                  }.with_missing_value_bucket(0))
                ],
                "doc_count_error_upper_bound" => 0,
                "sum_other_doc_count" => 2
              }
            }.with_missing_value_bucket(0, {
              "seasons_nested.notes" => {
                "meta" => inner_terms_meta({"grouping_fields" => ["seasons_nested.notes"], "key_path" => ["key"]}),
                "buckets" => [],
                "doc_count_error_upper_bound" => 0,
                "sum_other_doc_count" => 0
              }
            }.with_missing_value_bucket(0))
          }])
        end

        it "avoids performing a sub-aggregation when the sub-aggregation is requesting an empty page" do
          query = aggregation_query_of(name: "teams", sub_aggregations: [
            nested_sub_aggregation_of(path_in_index: ["seasons_nested"], query: sub_aggregation_query_of(
              name: "seasons_nested",
              first: 0,
              groupings: [field_term_grouping_of("seasons_nested", "year"), field_term_grouping_of("seasons_nested", "notes")]
            ))
          ])

          results = search_datastore_aggregations(query, index_def_name: "teams")

          expect(results).to eq([{"doc_count" => 0, "key" => {}}])
        end

        it "can group sub-aggregations on a single date field" do
          query = aggregation_query_of(name: "teams", sub_aggregations: [
            nested_sub_aggregation_of(path_in_index: ["seasons_nested"], query: sub_aggregation_query_of(name: "seasons_nested", groupings: [
              date_histogram_grouping_of("seasons_nested", "started_at", "year")
            ]))
          ])

          results = search_datastore_aggregations(query, index_def_name: "teams")

          expect(results).to eq([{
            "doc_count" => 0,
            "key" => {},
            "teams:seasons_nested" => {
              "doc_count" => 4,
              "meta" => outer_meta({"buckets_path" => ["seasons_nested.started_at"]}),
              "seasons_nested.started_at" => {
                "meta" => inner_date_meta({"grouping_fields" => ["seasons_nested.started_at"], "key_path" => ["key_as_string"]}),
                "buckets" => [
                  date_histogram_bucket(2020, 1),
                  date_histogram_bucket(2021, 1),
                  date_histogram_bucket(2022, 2)
                ]
              }
            }.with_missing_value_bucket(0)
          }])
        end

        it "can group sub-aggregations on a multiple date fields" do
          query = aggregation_query_of(name: "teams", sub_aggregations: [
            nested_sub_aggregation_of(path_in_index: ["seasons_nested"], query: sub_aggregation_query_of(name: "seasons_nested", groupings: [
              date_histogram_grouping_of("seasons_nested", "started_at", "year"),
              date_histogram_grouping_of("seasons_nested", "won_games_at", "year")
            ]))
          ])

          results = search_datastore_aggregations(query, index_def_name: "teams")

          expect(results).to eq([{
            "doc_count" => 0,
            "key" => {},
            "teams:seasons_nested" => {
              "doc_count" => 4,
              "meta" => outer_meta({"buckets_path" => ["seasons_nested.started_at"]}),
              "seasons_nested.started_at" => {
                "meta" => inner_date_meta({"grouping_fields" => ["seasons_nested.started_at"], "buckets_path" => ["seasons_nested.won_games_at"], "key_path" => ["key_as_string"]}),
                "buckets" => [
                  date_histogram_bucket(2020, 1, {"seasons_nested.won_games_at" => {
                    "meta" => inner_date_meta({"grouping_fields" => ["seasons_nested.won_games_at"], "key_path" => ["key_as_string"]}),
                    "buckets" => [date_histogram_bucket(2020, 1)]
                  }}.with_missing_value_bucket(0)),
                  date_histogram_bucket(2021, 1, {"seasons_nested.won_games_at" => {
                    "meta" => inner_date_meta({"grouping_fields" => ["seasons_nested.won_games_at"], "key_path" => ["key_as_string"]}),
                    "buckets" => [date_histogram_bucket(2021, 1)]
                  }}.with_missing_value_bucket(0)),
                  date_histogram_bucket(2022, 2, {"seasons_nested.won_games_at" => {
                    "meta" => inner_date_meta({"grouping_fields" => ["seasons_nested.won_games_at"], "key_path" => ["key_as_string"]}),
                    "buckets" => [date_histogram_bucket(2022, 2)]
                  }}.with_missing_value_bucket(0))
                ]
              }
            }.with_missing_value_bucket(0, {"seasons_nested.won_games_at" => {
              "meta" => inner_date_meta({"grouping_fields" => ["seasons_nested.won_games_at"], "key_path" => ["key_as_string"]}),
              "buckets" => []
            }}.with_missing_value_bucket(0))
          }])
        end

        it "can group sub-aggregations on a single non-date field and a single date field" do
          query = aggregation_query_of(name: "teams", sub_aggregations: [
            nested_sub_aggregation_of(path_in_index: ["seasons_nested"], query: sub_aggregation_query_of(name: "seasons_nested", groupings: [
              date_histogram_grouping_of("seasons_nested", "started_at", "year"),
              field_term_grouping_of("seasons_nested", "notes")
            ]))
          ])

          results = search_datastore_aggregations(query, index_def_name: "teams")

          expect(results).to eq([{
            "doc_count" => 0,
            "key" => {},
            "teams:seasons_nested" => {
              "meta" => outer_meta({"buckets_path" => ["seasons_nested.started_at"]}),
              "doc_count" => 4,
              "seasons_nested.started_at" => {
                "meta" => inner_date_meta({"buckets_path" => ["seasons_nested.notes"], "key_path" => ["key_as_string"], "grouping_fields" => ["seasons_nested.started_at"]}),
                "buckets" => [
                  date_histogram_bucket(2020, 1, {"seasons_nested.notes" => {
                    "meta" => inner_terms_meta({"key_path" => ["key"], "grouping_fields" => ["seasons_nested.notes"]}),
                    "doc_count_error_upper_bound" => 0,
                    "sum_other_doc_count" => 0,
                    "buckets" => [
                      term_bucket("old rules", 1),
                      term_bucket("pandemic", 1)
                    ]
                  }}.with_missing_value_bucket(0)),
                  date_histogram_bucket(2021, 1, {"seasons_nested.notes" => {
                    "meta" => inner_terms_meta({"key_path" => ["key"], "grouping_fields" => ["seasons_nested.notes"]}),
                    "doc_count_error_upper_bound" => 0,
                    "sum_other_doc_count" => 0,
                    "buckets" => [
                      term_bucket("old rules", 1)
                    ]
                  }}.with_missing_value_bucket(0)),
                  date_histogram_bucket(2022, 2, {"seasons_nested.notes" => {
                    "meta" => inner_terms_meta({"key_path" => ["key"], "grouping_fields" => ["seasons_nested.notes"]}),
                    "doc_count_error_upper_bound" => 0,
                    "sum_other_doc_count" => 0,
                    "buckets" => [
                      term_bucket("new rules", 2)
                    ]
                  }}.with_missing_value_bucket(0))
                ]
              }
            }.with_missing_value_bucket(0, {"seasons_nested.notes" => {
              "meta" => inner_terms_meta({"key_path" => ["key"], "grouping_fields" => ["seasons_nested.notes"]}),
              "doc_count_error_upper_bound" => 0,
              "sum_other_doc_count" => 0,
              "buckets" => []
            }}.with_missing_value_bucket(0))
          }])
        end

        it "can group sub-aggregations on multiple non-date fields and a single date field" do
          query = aggregation_query_of(name: "teams", sub_aggregations: [
            nested_sub_aggregation_of(path_in_index: ["seasons_nested"], query: sub_aggregation_query_of(name: "seasons_nested", groupings: [
              date_histogram_grouping_of("seasons_nested", "started_at", "year"),
              field_term_grouping_of("seasons_nested", "year"),
              field_term_grouping_of("seasons_nested", "notes")
            ]))
          ])

          results = search_datastore_aggregations(query, index_def_name: "teams")

          expect(results).to eq([{
            "doc_count" => 0,
            "key" => {},
            "teams:seasons_nested" => {
              "meta" => outer_meta({"buckets_path" => ["seasons_nested.started_at"]}),
              "doc_count" => 4,
              "seasons_nested.started_at" => {
                "meta" => inner_date_meta({"buckets_path" => ["seasons_nested.year"], "key_path" => ["key_as_string"], "grouping_fields" => ["seasons_nested.started_at"]}),
                "buckets" => [
                  date_histogram_bucket(2020, 1, {"seasons_nested.year" => {
                    "meta" => inner_terms_meta({"key_path" => ["key"], "grouping_fields" => ["seasons_nested.year"], "buckets_path" => ["seasons_nested.notes"]}),
                    "doc_count_error_upper_bound" => 0,
                    "sum_other_doc_count" => 0,
                    "buckets" => [
                      term_bucket(2020, 1, {"seasons_nested.notes" => {
                        "meta" => inner_terms_meta({"key_path" => ["key"], "grouping_fields" => ["seasons_nested.notes"]}),
                        "doc_count_error_upper_bound" => 0,
                        "sum_other_doc_count" => 0,
                        "buckets" => [
                          term_bucket("old rules", 1),
                          term_bucket("pandemic", 1)
                        ]
                      }}.with_missing_value_bucket(0))
                    ]
                  }}.with_missing_value_bucket(0, {"seasons_nested.notes" => {
                    "meta" => inner_terms_meta({"key_path" => ["key"], "grouping_fields" => ["seasons_nested.notes"]}),
                    "doc_count_error_upper_bound" => 0,
                    "sum_other_doc_count" => 0,
                    "buckets" => []
                  }}.with_missing_value_bucket(0))),
                  date_histogram_bucket(2021, 1, {"seasons_nested.year" => {
                    "meta" => inner_terms_meta({"key_path" => ["key"], "grouping_fields" => ["seasons_nested.year"], "buckets_path" => ["seasons_nested.notes"]}),
                    "doc_count_error_upper_bound" => 0,
                    "sum_other_doc_count" => 0,
                    "buckets" => [
                      term_bucket(2021, 1, {"seasons_nested.notes" => {
                        "meta" => inner_terms_meta({"key_path" => ["key"], "grouping_fields" => ["seasons_nested.notes"]}),
                        "doc_count_error_upper_bound" => 0,
                        "sum_other_doc_count" => 0,
                        "buckets" => [
                          term_bucket("old rules", 1)
                        ]
                      }}.with_missing_value_bucket(0))
                    ]
                  }}.with_missing_value_bucket(0, {"seasons_nested.notes" => {
                    "meta" => inner_terms_meta({"key_path" => ["key"], "grouping_fields" => ["seasons_nested.notes"]}),
                    "doc_count_error_upper_bound" => 0,
                    "sum_other_doc_count" => 0,
                    "buckets" => []
                  }}.with_missing_value_bucket(0))),
                  date_histogram_bucket(2022, 2, {"seasons_nested.year" => {
                    "meta" => inner_terms_meta({"key_path" => ["key"], "grouping_fields" => ["seasons_nested.year"], "buckets_path" => ["seasons_nested.notes"]}),
                    "doc_count_error_upper_bound" => 0,
                    "sum_other_doc_count" => 0,
                    "buckets" => [
                      term_bucket(2022, 2, {"seasons_nested.notes" => {
                        "meta" => inner_terms_meta({"key_path" => ["key"], "grouping_fields" => ["seasons_nested.notes"]}),
                        "doc_count_error_upper_bound" => 0,
                        "sum_other_doc_count" => 0,
                        "buckets" => [
                          term_bucket("new rules", 2)
                        ]
                      }}.with_missing_value_bucket(0))
                    ]
                  }}.with_missing_value_bucket(0, {"seasons_nested.notes" => {
                    "meta" => inner_terms_meta({"key_path" => ["key"], "grouping_fields" => ["seasons_nested.notes"]}),
                    "doc_count_error_upper_bound" => 0,
                    "sum_other_doc_count" => 0,
                    "buckets" => []
                  }}.with_missing_value_bucket(0)))
                ]
              }
            }.with_missing_value_bucket(0, {"seasons_nested.year" => {
              "meta" => inner_terms_meta({"key_path" => ["key"], "grouping_fields" => ["seasons_nested.year"], "buckets_path" => ["seasons_nested.notes"]}),
              "doc_count_error_upper_bound" => 0,
              "sum_other_doc_count" => 0,
              "buckets" => []
            }}.with_missing_value_bucket(0, {"seasons_nested.notes" => {
              "meta" => inner_terms_meta({"key_path" => ["key"], "grouping_fields" => ["seasons_nested.notes"]}),
              "doc_count_error_upper_bound" => 0,
              "sum_other_doc_count" => 0,
              "buckets" => []
            }}.with_missing_value_bucket(0)))
          }])
        end

        it "can group sub-aggregations on multiple non-date fields and multiple date fields" do
          query = aggregation_query_of(name: "teams", sub_aggregations: [
            nested_sub_aggregation_of(path_in_index: ["seasons_nested"], query: sub_aggregation_query_of(name: "seasons_nested", groupings: [
              date_histogram_grouping_of("seasons_nested", "started_at", "year"),
              date_histogram_grouping_of("seasons_nested", "won_games_at", "year"),
              field_term_grouping_of("seasons_nested", "year"),
              field_term_grouping_of("seasons_nested", "notes")
            ]))
          ])

          results = search_datastore_aggregations(query, index_def_name: "teams")

          expect(results).to eq([{
            "doc_count" => 0,
            "key" => {},
            "teams:seasons_nested" => {
              "meta" => outer_meta({"buckets_path" => ["seasons_nested.started_at"]}),
              "doc_count" => 4,
              "seasons_nested.started_at" => {
                "meta" => inner_date_meta({"buckets_path" => ["seasons_nested.won_games_at"], "key_path" => ["key_as_string"], "grouping_fields" => ["seasons_nested.started_at"]}),
                "buckets" => [
                  date_histogram_bucket(2020, 1, {"seasons_nested.won_games_at" => {
                    "meta" => inner_date_meta({"buckets_path" => ["seasons_nested.year"], "key_path" => ["key_as_string"], "grouping_fields" => ["seasons_nested.won_games_at"]}),
                    "buckets" => [
                      date_histogram_bucket(2020, 1, {"seasons_nested.year" => {
                        "meta" => inner_terms_meta({"buckets_path" => ["seasons_nested.notes"], "key_path" => ["key"], "grouping_fields" => ["seasons_nested.year"]}),
                        "doc_count_error_upper_bound" => 0,
                        "sum_other_doc_count" => 0,
                        "buckets" => [
                          term_bucket(2020, 1, {"seasons_nested.notes" => {
                            "meta" => inner_terms_meta({"key_path" => ["key"], "grouping_fields" => ["seasons_nested.notes"]}),
                            "doc_count_error_upper_bound" => 0,
                            "sum_other_doc_count" => 0,
                            "buckets" => [
                              term_bucket("old rules", 1),
                              term_bucket("pandemic", 1)
                            ]
                          }}.with_missing_value_bucket(0))
                        ]
                      }}.with_missing_value_bucket(0, {"seasons_nested.notes" => {
                        "meta" => inner_terms_meta({"key_path" => ["key"], "grouping_fields" => ["seasons_nested.notes"]}),
                        "doc_count_error_upper_bound" => 0,
                        "sum_other_doc_count" => 0,
                        "buckets" => []
                      }}.with_missing_value_bucket(0)))
                    ]
                  }}.with_missing_value_bucket(0, {"seasons_nested.year" => {
                    "meta" => inner_terms_meta({"buckets_path" => ["seasons_nested.notes"], "key_path" => ["key"], "grouping_fields" => ["seasons_nested.year"]}),
                    "doc_count_error_upper_bound" => 0,
                    "sum_other_doc_count" => 0,
                    "buckets" => []
                  }}.with_missing_value_bucket(0, {"seasons_nested.notes" => {
                    "meta" => inner_terms_meta({"key_path" => ["key"], "grouping_fields" => ["seasons_nested.notes"]}),
                    "doc_count_error_upper_bound" => 0,
                    "sum_other_doc_count" => 0,
                    "buckets" => []
                  }}.with_missing_value_bucket(0)))),
                  date_histogram_bucket(2021, 1, {"seasons_nested.won_games_at" => {
                    "meta" => inner_date_meta({"buckets_path" => ["seasons_nested.year"], "key_path" => ["key_as_string"], "grouping_fields" => ["seasons_nested.won_games_at"]}),
                    "buckets" => [
                      date_histogram_bucket(2021, 1, {"seasons_nested.year" => {
                        "meta" => inner_terms_meta({"buckets_path" => ["seasons_nested.notes"], "key_path" => ["key"], "grouping_fields" => ["seasons_nested.year"]}),
                        "doc_count_error_upper_bound" => 0,
                        "sum_other_doc_count" => 0,
                        "buckets" => [
                          term_bucket(2021, 1, {"seasons_nested.notes" => {
                            "meta" => inner_terms_meta({"key_path" => ["key"], "grouping_fields" => ["seasons_nested.notes"]}),
                            "doc_count_error_upper_bound" => 0,
                            "sum_other_doc_count" => 0,
                            "buckets" => [
                              term_bucket("old rules", 1)
                            ]
                          }}.with_missing_value_bucket(0))
                        ]
                      }}.with_missing_value_bucket(0, {"seasons_nested.notes" => {
                        "meta" => inner_terms_meta({"key_path" => ["key"], "grouping_fields" => ["seasons_nested.notes"]}),
                        "doc_count_error_upper_bound" => 0,
                        "sum_other_doc_count" => 0,
                        "buckets" => []
                      }}.with_missing_value_bucket(0)))
                    ]
                  }}.with_missing_value_bucket(0, {"seasons_nested.year" => {
                    "meta" => inner_terms_meta({"buckets_path" => ["seasons_nested.notes"], "key_path" => ["key"], "grouping_fields" => ["seasons_nested.year"]}),
                    "doc_count_error_upper_bound" => 0,
                    "sum_other_doc_count" => 0,
                    "buckets" => []
                  }}.with_missing_value_bucket(0, {"seasons_nested.notes" => {
                    "meta" => inner_terms_meta({"key_path" => ["key"], "grouping_fields" => ["seasons_nested.notes"]}),
                    "doc_count_error_upper_bound" => 0,
                    "sum_other_doc_count" => 0,
                    "buckets" => []
                  }}.with_missing_value_bucket(0)))),
                  date_histogram_bucket(2022, 2, {"seasons_nested.won_games_at" => {
                    "meta" => inner_date_meta({"buckets_path" => ["seasons_nested.year"], "key_path" => ["key_as_string"], "grouping_fields" => ["seasons_nested.won_games_at"]}),
                    "buckets" => [
                      date_histogram_bucket(2022, 2, {"seasons_nested.year" => {
                        "meta" => inner_terms_meta({"buckets_path" => ["seasons_nested.notes"], "key_path" => ["key"], "grouping_fields" => ["seasons_nested.year"]}),
                        "doc_count_error_upper_bound" => 0,
                        "sum_other_doc_count" => 0,
                        "buckets" => [
                          term_bucket(2022, 2, {"seasons_nested.notes" => {
                            "meta" => inner_terms_meta({"key_path" => ["key"], "grouping_fields" => ["seasons_nested.notes"]}),
                            "doc_count_error_upper_bound" => 0,
                            "sum_other_doc_count" => 0,
                            "buckets" => [
                              term_bucket("new rules", 2)
                            ]
                          }}.with_missing_value_bucket(0))
                        ]
                      }}.with_missing_value_bucket(0, {"seasons_nested.notes" => {
                        "meta" => inner_terms_meta({"key_path" => ["key"], "grouping_fields" => ["seasons_nested.notes"]}),
                        "doc_count_error_upper_bound" => 0,
                        "sum_other_doc_count" => 0,
                        "buckets" => []
                      }}.with_missing_value_bucket(0)))
                    ]
                  }}.with_missing_value_bucket(0, {"seasons_nested.year" => {
                    "meta" => inner_terms_meta({"buckets_path" => ["seasons_nested.notes"], "key_path" => ["key"], "grouping_fields" => ["seasons_nested.year"]}),
                    "doc_count_error_upper_bound" => 0,
                    "sum_other_doc_count" => 0,
                    "buckets" => []
                  }}.with_missing_value_bucket(0, {"seasons_nested.notes" => {
                    "meta" => inner_terms_meta({"key_path" => ["key"], "grouping_fields" => ["seasons_nested.notes"]}),
                    "doc_count_error_upper_bound" => 0,
                    "sum_other_doc_count" => 0,
                    "buckets" => []
                  }}.with_missing_value_bucket(0))))
                ]
              }
            }.with_missing_value_bucket(0, {"seasons_nested.won_games_at" => {
              "meta" => inner_date_meta({"buckets_path" => ["seasons_nested.year"], "key_path" => ["key_as_string"], "grouping_fields" => ["seasons_nested.won_games_at"]}),
              "buckets" => []
            }}.with_missing_value_bucket(0, {"seasons_nested.year" => {
              "meta" => inner_terms_meta({"buckets_path" => ["seasons_nested.notes"], "key_path" => ["key"], "grouping_fields" => ["seasons_nested.year"]}),
              "doc_count_error_upper_bound" => 0,
              "sum_other_doc_count" => 0,
              "buckets" => []
            }}.with_missing_value_bucket(0, {"seasons_nested.notes" => {
              "meta" => inner_terms_meta({"key_path" => ["key"], "grouping_fields" => ["seasons_nested.notes"]}),
              "doc_count_error_upper_bound" => 0,
              "sum_other_doc_count" => 0,
              "buckets" => []
            }}.with_missing_value_bucket(0))))
          }])
        end

        it "accounts for an extra filtering layer in the `buckets_path` meta" do
          query = aggregation_query_of(name: "teams", sub_aggregations: [
            nested_sub_aggregation_of(path_in_index: ["seasons_nested"], query: sub_aggregation_query_of(
              name: "seasons_nested",
              groupings: [field_term_grouping_of("seasons_nested", "year")],
              filter: {"year" => {"gt" => 2020}}
            ))
          ])

          results = search_datastore_aggregations(query, index_def_name: "teams")

          expect(results).to eq([{
            "doc_count" => 0,
            "key" => {},
            "teams:seasons_nested" => {
              "doc_count" => 4,
              "meta" => outer_meta({"buckets_path" => ["seasons_nested:filtered", "seasons_nested.year"]}),
              "seasons_nested:filtered" => {
                "doc_count" => 3,
                "seasons_nested.year" => {
                  "meta" => inner_terms_meta({"grouping_fields" => ["seasons_nested.year"], "key_path" => ["key"]}),
                  "buckets" => [
                    term_bucket(2022, 2),
                    term_bucket(2021, 1)
                  ],
                  "doc_count_error_upper_bound" => 0,
                  "sum_other_doc_count" => 0
                }
              }.with_missing_value_bucket(0)
            }
          }])
        end

        it "ignores date histogram buckets that have no documents in them" do
          index_into(
            graphql,
            build(
              :team,
              seasons: [
                build(:team_season, year: 2000, notes: ["old rules"], players: [])
              ]
            )
          )

          query = aggregation_query_of(name: "teams", sub_aggregations: [
            nested_sub_aggregation_of(path_in_index: ["seasons_nested"], query: sub_aggregation_query_of(name: "seasons_nested", groupings: [
              date_histogram_grouping_of("seasons_nested", "started_at", "year")
            ]))
          ])

          results = search_datastore_aggregations(query, index_def_name: "teams")

          expect(results.dig(0, "teams:seasons_nested", "seasons_nested.started_at", "buckets")).to eq([
            date_histogram_bucket(2000, 1),
            # Notice no buckets between 2000 and 2020 in spite of the gaps.
            date_histogram_bucket(2020, 1),
            date_histogram_bucket(2021, 1),
            date_histogram_bucket(2022, 2)
          ])
        end

        it "gets `doc_count_error_upper_bound` based on the `needs_doc_count_error` query flag" do
          buckets_for_true, buckets_for_false = [true, false].map do |needs_doc_count_error|
            query = aggregation_query_of(name: "teams", sub_aggregations: [
              nested_sub_aggregation_of(path_in_index: ["seasons_nested"], query: sub_aggregation_query_of(
                name: "seasons_nested",
                needs_doc_count_error: needs_doc_count_error,
                groupings: [field_term_grouping_of("seasons_nested", "year")]
              ))
            ])

            results = search_datastore_aggregations(query, index_def_name: "teams")
            results.dig(0, "teams:seasons_nested", "seasons_nested.year", "buckets")
          end

          expect(buckets_for_true).to eq [
            {"doc_count" => 2, "key" => 2022, "doc_count_error_upper_bound" => 0},
            {"doc_count" => 1, "key" => 2020, "doc_count_error_upper_bound" => 0},
            {"doc_count" => 1, "key" => 2021, "doc_count_error_upper_bound" => 0}
          ]

          expect(buckets_for_false).to eq [
            {"doc_count" => 2, "key" => 2022},
            {"doc_count" => 1, "key" => 2020},
            {"doc_count" => 1, "key" => 2021}
          ]
        end
      end

      context "with groupings (using the `CompositeGroupingAdapter`)" do
        include_context "sub-aggregation support", Aggregation::CompositeGroupingAdapter

        it "supports multiple groupings, aggregated values, and count" do
          query = aggregation_query_of(name: "teams", sub_aggregations: [
            nested_sub_aggregation_of(path_in_index: ["seasons_nested"], query: sub_aggregation_query_of(
              name: "seasons_nested",
              needs_doc_count: true,
              computations: [
                computation_of("seasons_nested", "year", :min, computed_field_name: "exact_min"),
                computation_of("seasons_nested", "the_record", "win_count", :max, computed_field_name: "exact_max"),
                computation_of("seasons_nested", "the_record", "win_count", :avg, computed_field_name: "approximate_avg")
              ],
              groupings: [
                date_histogram_grouping_of("seasons_nested", "started_at", "year"),
                field_term_grouping_of("seasons_nested", "year"),
                field_term_grouping_of("seasons_nested", "notes")
              ]
            ))
          ])

          results = search_datastore_aggregations(query, index_def_name: "teams")

          expect(results.dig(0, "teams:seasons_nested")).to eq({
            "meta" => outer_meta({"buckets_path" => ["seasons_nested"]}),
            "doc_count" => 4,
            "seasons_nested" => {
              "after_key" => {
                "seasons_nested.started_at" => "2022-01-01T00:00:00.000Z",
                "seasons_nested.year" => 2022,
                "seasons_nested.notes" => "new rules"
              },
              "buckets" => [
                {
                  "key" => {
                    "seasons_nested.started_at" => "2020-01-01T00:00:00.000Z",
                    "seasons_nested.year" => 2020,
                    "seasons_nested.notes" => "old rules"
                  },
                  "doc_count" => 1,
                  "seasons_nested:seasons_nested.year:exact_min" => {"value" => 2020.0},
                  "seasons_nested:seasons_nested.the_record.win_count:exact_max" => {"value" => 30.0},
                  "seasons_nested:seasons_nested.the_record.win_count:approximate_avg" => {"value" => 30.0}
                },
                {
                  "key" => {
                    "seasons_nested.started_at" => "2020-01-01T00:00:00.000Z",
                    "seasons_nested.year" => 2020,
                    "seasons_nested.notes" => "pandemic"
                  },
                  "doc_count" => 1,
                  "seasons_nested:seasons_nested.year:exact_min" => {"value" => 2020.0},
                  "seasons_nested:seasons_nested.the_record.win_count:exact_max" => {"value" => 30.0},
                  "seasons_nested:seasons_nested.the_record.win_count:approximate_avg" => {"value" => 30.0}
                },
                {
                  "key" => {
                    "seasons_nested.started_at" => "2021-01-01T00:00:00.000Z",
                    "seasons_nested.year" => 2021,
                    "seasons_nested.notes" => "old rules"
                  },
                  "doc_count" => 1,
                  "seasons_nested:seasons_nested.year:exact_min" => {"value" => 2021.0},
                  "seasons_nested:seasons_nested.the_record.win_count:exact_max" => {"value" => 60.0},
                  "seasons_nested:seasons_nested.the_record.win_count:approximate_avg" => {"value" => 60.0}
                },
                {
                  "key" => {
                    "seasons_nested.started_at" => "2022-01-01T00:00:00.000Z",
                    "seasons_nested.year" => 2022,
                    "seasons_nested.notes" => "new rules"
                  },
                  "doc_count" => 2,
                  "seasons_nested:seasons_nested.year:exact_min" => {"value" => 2022.0},
                  "seasons_nested:seasons_nested.the_record.win_count:exact_max" => {"value" => 50.0},
                  "seasons_nested:seasons_nested.the_record.win_count:approximate_avg" => {"value" => 45.0}
                }
              ]
            }
          })
        end
      end

      def term_bucket(key_or_keys, count, extra_fields = {})
        {
          "key" => key_or_keys,
          "doc_count" => count
        }.compact.merge(extra_fields)
      end

      def date_histogram_bucket(year, count, extra_fields = {})
        time = ::Time.iso8601("#{year}-01-01T00:00:00Z")
        {
          "key" => time.to_i * 1000,
          "key_as_string" => time.iso8601(3),
          "doc_count" => count
        }.merge(extra_fields)
      end
    end
  end
end
