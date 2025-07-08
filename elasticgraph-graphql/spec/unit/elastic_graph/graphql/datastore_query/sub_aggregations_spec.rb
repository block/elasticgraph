# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require_relative "datastore_query_unit_support"
require "support/aggregations_helpers"
require "support/sub_aggregation_support"

module ElasticGraph
  class GraphQL
    module SubAggregationQueryRefinements
      refine ::Hash do
        # Helper method that can be used to add a missing value bucket aggregation to an
        # existing aggregation hash. Defined as a refinement to support a chainable syntax
        # in order to minimize churn in our specs at the point we added missing value buckets.
        def with_missing_value_agg
          grouped_field = SubAggregationQueryRefinements.grouped_field_from(self)
          grouped_sub_hash = fetch(grouped_field)
          copied_entries = grouped_sub_hash.key?("aggs") ? grouped_sub_hash.slice("meta", "aggs") : {}
          missing_agg_hash = copied_entries.merge({"missing" => {"field" => grouped_field}})

          merge({Aggregation::Key.missing_value_bucket_key(grouped_field) => missing_agg_hash})
        end
      end

      extend ::RSpec::Matchers

      def self.grouped_field_from(agg_hash)
        grouped_field_candidates = agg_hash.except("aggs", "meta").keys

        # We expect only one candidate; here we use an expectation that will show them all if there are more.
        expect(grouped_field_candidates).to eq([grouped_field_candidates.first])
        grouped_field_candidates.first
      end
    end

    RSpec.describe DatastoreQuery, "sub-aggregations" do
      using SubAggregationQueryRefinements
      include_context "DatastoreQueryUnitSupport"
      include_context "sub-aggregation support", Aggregation::NonCompositeGroupingAdapter

      it "excludes a sub-aggregation requesting an empty page from the generated query body" do
        query = new_query(aggregations: [aggregation_query_of(name: "teams", sub_aggregations: [
          nested_sub_aggregation_of(path_in_index: ["current_players_nested"], query: sub_aggregation_query_of(name: "current_players_nested", first: 0))
        ])])

        expect(datastore_body_of(query)).to exclude_aggs
      end

      it "builds a `nested` aggregation query for a nested sub-aggregation" do
        query = new_query(aggregations: [aggregation_query_of(name: "teams", sub_aggregations: [
          nested_sub_aggregation_of(path_in_index: ["current_players_nested"], query: sub_aggregation_query_of(name: "current_players_nested", first: 12)),
          nested_sub_aggregation_of(path_in_index: ["seasons_nested"], query: sub_aggregation_query_of(name: "seasons_nested", first: 9))
        ])])

        expect(datastore_body_of(query)).to include_aggs({
          "teams:current_players_nested" => {"nested" => {"path" => "current_players_nested"}, "meta" => outer_meta(size: 12)},
          "teams:seasons_nested" => {"nested" => {"path" => "seasons_nested"}, "meta" => outer_meta(size: 9)}
        })
      end

      it "builds sub-aggregations of sub-aggregations of sub-aggregations when the query has that structure" do
        query = new_query(aggregations: [aggregation_query_of(name: "teams", sub_aggregations: [
          nested_sub_aggregation_of(path_in_index: ["seasons_nested"], query: sub_aggregation_query_of(
            name: "seasons_nested",
            first: 14,
            sub_aggregations: [
              nested_sub_aggregation_of(path_in_index: ["seasons_nested", "players_nested"], query: sub_aggregation_query_of(
                name: "players_nested",
                first: 15,
                sub_aggregations: [
                  nested_sub_aggregation_of(path_in_index: ["seasons_nested", "players_nested", "seasons_nested"], query: sub_aggregation_query_of(
                    name: "seasons_nested",
                    first: 16
                  ))
                ]
              ))
            ]
          ))
        ])])

        expect(datastore_body_of(query)).to include_aggs({
          "teams:seasons_nested" => {
            "nested" => {"path" => "seasons_nested"},
            "meta" => outer_meta(size: 14),
            "aggs" => {
              "teams:seasons_nested:seasons_nested.players_nested" => {
                "nested" => {"path" => "seasons_nested.players_nested"},
                "meta" => outer_meta(size: 15),
                "aggs" => {
                  "teams:seasons_nested:players_nested:seasons_nested.players_nested.seasons_nested" => {
                    "nested" => {"path" => "seasons_nested.players_nested.seasons_nested"},
                    "meta" => outer_meta(size: 16)
                  }
                }
              }
            }
          }
        })
      end

      it "supports nesting sub-aggreations under an extra object layer" do
        query = new_query(aggregations: [aggregation_query_of(name: "teams", sub_aggregations: [
          nested_sub_aggregation_of(path_in_index: ["the_nested_fields", "current_players"], query: sub_aggregation_query_of(name: "current_players"))
        ])])

        expect(datastore_body_of(query)).to include_aggs({
          "teams:the_nested_fields.current_players" => {
            "nested" => {"path" => "the_nested_fields.current_players"},
            "meta" => outer_meta
          }
        })
      end

      it "can handle sub-aggregation fields of the same name under parents of a different name" do
        query = new_query(aggregations: [aggregation_query_of(name: "team_aggregations", sub_aggregations: [
          nested_sub_aggregation_of(
            path_in_index: ["nested_fields", "seasons"],
            query: sub_aggregation_query_of(
              name: "seasons",
              computations: [computation_of("nested_fields", "seasons", "year", :min, computed_field_name: "exact_min")]
            )
          ),
          nested_sub_aggregation_of(
            path_in_index: ["nested_fields2", "seasons"],
            query: sub_aggregation_query_of(
              name: "seasons",
              computations: [computation_of("nested_fields2", "seasons", "year", :min, computed_field_name: "exact_min")]
            )
          )
        ])])

        expect(datastore_body_of(query)).to include_aggs({
          "team_aggregations:nested_fields.seasons" => {
            "aggs" => {
              "seasons:nested_fields.seasons.year:exact_min" => {
                "min" => {"field" => "nested_fields.seasons.year"}
              }
            },
            "meta" => outer_meta,
            "nested" => {"path" => "nested_fields.seasons"}
          },
          "team_aggregations:nested_fields2.seasons" => {
            "aggs" => {
              "seasons:nested_fields2.seasons.year:exact_min" => {
                "min" => {"field" => "nested_fields2.seasons.year"}
              }
            },
            "meta" => outer_meta,
            "nested" => {"path" => "nested_fields2.seasons"}
          }
        })
      end

      it "supports filtered sub-aggregations" do
        query = new_query(aggregations: [aggregation_query_of(name: "teams", sub_aggregations: [
          nested_sub_aggregation_of(path_in_index: ["current_players_nested"], query: sub_aggregation_query_of(name: "current_players_nested", filter: {
            "name" => {"equal_to_any_of" => %w[Dan Ted Bob]}
          }))
        ])])

        expect(datastore_body_of(query)).to include_aggs({
          "teams:current_players_nested" => {
            "meta" => outer_meta({"bucket_path" => ["current_players_nested:filtered"]}),
            "nested" => {"path" => "current_players_nested"},
            "aggs" => {
              "current_players_nested:filtered" => {
                "filter" => {
                  bool: {filter: [{terms: {"current_players_nested.name" => ["Dan", "Ted", "Bob"]}}]}
                }
              }
            }
          }
        })
      end

      it "allows sub-aggregations to filter on the count of list fields" do
        query = new_query(aggregations: [aggregation_query_of(name: "teams", sub_aggregations: [
          nested_sub_aggregation_of(path_in_index: ["current_players_nested"], query: sub_aggregation_query_of(name: "current_players_nested", filter: {
            "seasons_nested" => {LIST_COUNTS_FIELD => {"gt" => 1}}
          }))
        ])])

        expect(datastore_body_of(query)).to include_aggs({
          "teams:current_players_nested" => {
            "meta" => outer_meta({"bucket_path" => ["current_players_nested:filtered"]}),
            "nested" => {"path" => "current_players_nested"},
            "aggs" => {
              "current_players_nested:filtered" => {
                "filter" => {
                  bool: {filter: [{range: {"current_players_nested.#{LIST_COUNTS_FIELD}.seasons_nested" => {gt: 1}}}]}
                }
              }
            }
          }
        })
      end

      it "treats empty filters treating as `true`" do
        query = new_query(aggregations: [aggregation_query_of(name: "teams", sub_aggregations: [
          nested_sub_aggregation_of(path_in_index: ["current_players_nested"], query: sub_aggregation_query_of(name: "current_players_nested", filter: {
            "name" => {"equal_to_any_of" => nil}
          }))
        ])])

        expect(datastore_body_of(query)).to include_aggs({
          "teams:current_players_nested" => {
            "nested" => {"path" => "current_players_nested"},
            "meta" => outer_meta
          }
        })
      end

      it "supports sub-aggregations under a filtered sub-aggregation" do
        query = new_query(aggregations: [aggregation_query_of(name: "teams", sub_aggregations: [
          nested_sub_aggregation_of(path_in_index: ["current_players_nested"], query: sub_aggregation_query_of(
            name: "current_players_nested",
            filter: {"name" => {"equal_to_any_of" => %w[Dan Ted Bob]}},
            sub_aggregations: [nested_sub_aggregation_of(
              path_in_index: ["current_players_nested", "seasons_nested"],
              query: sub_aggregation_query_of(name: "seasons_nested")
            )]
          ))
        ])])

        expect(datastore_body_of(query)).to include_aggs({
          "teams:current_players_nested" => {
            "meta" => outer_meta({"bucket_path" => ["current_players_nested:filtered"]}),
            "nested" => {"path" => "current_players_nested"},
            "aggs" => {
              "current_players_nested:filtered" => {
                "filter" => {
                  bool: {filter: [{terms: {"current_players_nested.name" => ["Dan", "Ted", "Bob"]}}]}
                },
                "aggs" => {
                  "teams:current_players_nested:current_players_nested.seasons_nested" => {
                    "nested" => {"path" => "current_players_nested.seasons_nested"},
                    "meta" => outer_meta
                  }
                }
              }
            }
          }
        })
      end

      it "supports filtered sub-aggregations under a filtered sub-aggregation" do
        query = new_query(aggregations: [aggregation_query_of(name: "teams", sub_aggregations: [
          nested_sub_aggregation_of(path_in_index: ["current_players_nested"], query: sub_aggregation_query_of(
            name: "current_players_nested",
            filter: {"name" => {"equal_to_any_of" => %w[Dan Ted Bob]}},
            sub_aggregations: [nested_sub_aggregation_of(
              path_in_index: ["current_players_nested", "seasons_nested"],
              query: sub_aggregation_query_of(name: "seasons_nested", filter: {"year" => {"gt" => 2020}})
            )]
          ))
        ])])

        expect(datastore_body_of(query)).to include_aggs({
          "teams:current_players_nested" => {
            "meta" => outer_meta({"bucket_path" => ["current_players_nested:filtered"]}),
            "nested" => {"path" => "current_players_nested"},
            "aggs" => {
              "current_players_nested:filtered" => {
                "filter" => {
                  bool: {filter: [{terms: {"current_players_nested.name" => ["Dan", "Ted", "Bob"]}}]}
                },
                "aggs" => {
                  "teams:current_players_nested:current_players_nested.seasons_nested" => {
                    "meta" => outer_meta({"bucket_path" => ["seasons_nested:filtered"]}),
                    "nested" => {"path" => "current_players_nested.seasons_nested"},
                    "aggs" => {
                      "seasons_nested:filtered" => {
                        "filter" => {
                          bool: {filter: [{range: {"current_players_nested.seasons_nested.year" => {gt: 2020}}}]}
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        })
      end

      context "with computations" do
        it "supports ungrouped aggregated values" do
          query = new_query(aggregations: [aggregation_query_of(name: "teams", sub_aggregations: [
            nested_sub_aggregation_of(path_in_index: ["seasons_nested"], query: sub_aggregation_query_of(name: "seasons_nested", computations: [
              computation_of("seasons_nested", "year", :min, computed_field_name: "exact_min"),
              computation_of("seasons_nested", "the_record", "win_count", :max, computed_field_name: "exact_max"),
              computation_of("seasons_nested", "the_record", "win_count", :avg, computed_field_name: "approximate_avg")
            ]))
          ])])

          expect(datastore_body_of(query)).to include_aggs({
            "teams:seasons_nested" => {
              "nested" => {"path" => "seasons_nested"},
              "meta" => outer_meta,
              "aggs" => {
                "seasons_nested:seasons_nested.the_record.win_count:approximate_avg" => {
                  "avg" => {"field" => "seasons_nested.the_record.win_count"}
                },
                "seasons_nested:seasons_nested.the_record.win_count:exact_max" => {
                  "max" => {"field" => "seasons_nested.the_record.win_count"}
                },
                "seasons_nested:seasons_nested.year:exact_min" => {
                  "min" => {"field" => "seasons_nested.year"}
                }
              }
            }
          })
        end

        it "uses the GraphQL query field names in the aggregation key when they differ from the field names in the index" do
          query = new_query(aggregations: [aggregation_query_of(name: "teams", sub_aggregations: [
            nested_sub_aggregation_of(path_in_index: ["seasons_nested"], query: sub_aggregation_query_of(name: "seasons_nested", computations: [
              computation_of("seasons_nested", "year", :min, computed_field_name: "exact_min", field_names_in_graphql_query: ["sea_nest", "the_year"]),
              computation_of("seasons_nested", "the_record", "win_count", :avg, computed_field_name: "approximate_avg", field_names_in_graphql_query: ["sea_nest", "rec", "wins"])
            ]))
          ])])

          expect(datastore_body_of(query)).to include_aggs({
            "teams:seasons_nested" => {
              "nested" => {"path" => "seasons_nested"},
              "meta" => outer_meta,
              "aggs" => {
                "seasons_nested:sea_nest.rec.wins:approximate_avg" => {
                  "avg" => {"field" => "seasons_nested.the_record.win_count"}
                },
                "seasons_nested:sea_nest.the_year:exact_min" => {
                  "min" => {"field" => "seasons_nested.year"}
                }
              }
            }
          })
        end

        it "supports filtered aggregated values" do
          query = new_query(aggregations: [aggregation_query_of(name: "teams", sub_aggregations: [
            nested_sub_aggregation_of(path_in_index: ["seasons_nested"], query: sub_aggregation_query_of(
              name: "seasons_nested",
              filter: {"year" => {"gt" => 2021}},
              computations: [
                computation_of("seasons_nested", "year", :min, computed_field_name: "exact_min")
              ]
            ))
          ])])

          expect(datastore_body_of(query)).to include_aggs({
            "teams:seasons_nested" => {
              "nested" => {"path" => "seasons_nested"},
              "aggs" => {
                "seasons_nested:filtered" => {
                  "filter" => {bool: {filter: [{range: {"seasons_nested.year" => {gt: 2021}}}]}},
                  "aggs" => {
                    "seasons_nested:seasons_nested.year:exact_min" => {
                      "min" => {"field" => "seasons_nested.year"}
                    }
                  }
                }
              },
              "meta" => outer_meta({"bucket_path" => ["seasons_nested:filtered"]})
            }
          })
        end

        it "supports grouped aggregated values" do
          query = new_query(aggregations: [aggregation_query_of(name: "teams", sub_aggregations: [
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
          ])])

          expect(datastore_body_of(query)).to include_aggs({
            "teams:seasons_nested" => {
              "nested" => {"path" => "seasons_nested"},
              "meta" => outer_meta({"buckets_path" => ["seasons_nested.notes"]}),
              "aggs" => {
                "seasons_nested.notes" => {
                  "meta" => inner_terms_meta({"grouping_fields" => ["seasons_nested.notes"], "key_path" => ["key"]}),
                  "terms" => terms({"field" => "seasons_nested.notes", "collect_mode" => "depth_first"}),
                  "aggs" => {
                    "seasons_nested:seasons_nested.year:exact_min" => {
                      "min" => {"field" => "seasons_nested.year"}
                    },
                    "seasons_nested:seasons_nested.the_record.win_count:exact_max" => {
                      "max" => {"field" => "seasons_nested.the_record.win_count"}
                    },
                    "seasons_nested:seasons_nested.the_record.win_count:approximate_avg" => {
                      "avg" => {"field" => "seasons_nested.the_record.win_count"}
                    }
                  }
                }
              }.with_missing_value_agg
            }
          })
        end

        it "uses the GraphQL query field name (instead of the `name_in_index`) for `grouping_fields` meta on terms groupings" do
          query = new_query(aggregations: [aggregation_query_of(name: "teams", sub_aggregations: [
            nested_sub_aggregation_of(path_in_index: ["seasons_nested"], query: sub_aggregation_query_of(
              name: "seasons_nested",
              computations: [
                computation_of("seasons_nested", "year", :min, computed_field_name: "exact_min")
              ],
              groupings: [
                field_term_grouping_of("seasons_nested", "notes", field_names_in_graphql_query: ["sea_nest", "the_notes"])
              ]
            ))
          ])])

          expect(datastore_body_of(query).dig(:aggs, "teams:seasons_nested", "aggs", "sea_nest.the_notes", "meta")).to eq(
            inner_terms_meta({"grouping_fields" => ["sea_nest.the_notes"], "key_path" => ["key"]})
          )
        end

        it "supports aggregated values on multiple levels of sub-aggregations" do
          query = new_query(aggregations: [aggregation_query_of(name: "teams", sub_aggregations: [
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
          ])])

          expect(datastore_body_of(query)).to include_aggs({
            "teams:seasons_nested" => {
              "nested" => {"path" => "seasons_nested"},
              "meta" => outer_meta,
              "aggs" => {
                "seasons_nested:seasons_nested.year:min" => {
                  "min" => {"field" => "seasons_nested.year"}
                },
                "teams:seasons_nested:seasons_nested.players_nested" => {
                  "nested" => {"path" => "seasons_nested.players_nested"},
                  "meta" => outer_meta,
                  "aggs" => {
                    "players_nested:seasons_nested.players_nested.name:cardinality" => {
                      "cardinality" => {"field" => "seasons_nested.players_nested.name"}
                    },
                    "teams:seasons_nested:players_nested:seasons_nested.players_nested.seasons_nested" => {
                      "nested" => {"path" => "seasons_nested.players_nested.seasons_nested"},
                      "meta" => outer_meta,
                      "aggs" => {
                        "seasons_nested:seasons_nested.players_nested.seasons_nested.year:max" => {
                          "max" => {"field" => "seasons_nested.players_nested.seasons_nested.year"}
                        }
                      }
                    }
                  }
                }
              }
            }
          })
        end
      end

      context "with groupings (using the `NonCompositeGroupingAdapter`)" do
        include_context "sub-aggregation support", Aggregation::NonCompositeGroupingAdapter

        it "can group sub-aggregations on a single non-date field" do
          query = new_query(aggregations: [aggregation_query_of(name: "teams", sub_aggregations: [
            nested_sub_aggregation_of(path_in_index: ["seasons_nested"], query: sub_aggregation_query_of(name: "seasons_nested", groupings: [
              field_term_grouping_of("seasons_nested", "year")
            ]))
          ])])

          expect(datastore_body_of(query)).to include_aggs({
            "teams:seasons_nested" => {
              "nested" => {"path" => "seasons_nested"},
              "meta" => outer_meta({"buckets_path" => ["seasons_nested.year"]}),
              "aggs" => {
                "seasons_nested.year" => {
                  "meta" => inner_terms_meta({"grouping_fields" => ["seasons_nested.year"], "key_path" => ["key"]}),
                  "terms" => terms({"field" => "seasons_nested.year", "collect_mode" => "depth_first"})
                }
              }.with_missing_value_agg
            }
          })
        end

        it "can group sub-aggregations on multiple non-date fields" do
          query = new_query(aggregations: [aggregation_query_of(name: "teams", sub_aggregations: [
            nested_sub_aggregation_of(path_in_index: ["seasons_nested"], query: sub_aggregation_query_of(name: "seasons_nested", groupings: [
              field_term_grouping_of("seasons_nested", "year"),
              field_term_grouping_of("seasons_nested", "notes")
            ]))
          ])])

          expect(datastore_body_of(query)).to include_aggs({
            "teams:seasons_nested" => {
              "nested" => {"path" => "seasons_nested"},
              "meta" => outer_meta({"buckets_path" => ["seasons_nested.year"]}),
              "aggs" => {
                "seasons_nested.year" => {
                  "meta" => inner_terms_meta({"grouping_fields" => ["seasons_nested.year"], "key_path" => ["key"], "buckets_path" => ["seasons_nested.notes"]}),
                  "terms" => terms({"field" => "seasons_nested.year", "collect_mode" => "depth_first"}),
                  "aggs" => {
                    "seasons_nested.notes" => {
                      "meta" => inner_terms_meta({"grouping_fields" => ["seasons_nested.notes"], "key_path" => ["key"]}),
                      "terms" => terms({"field" => "seasons_nested.notes", "collect_mode" => "depth_first"})
                    }
                  }.with_missing_value_agg
                }
              }.with_missing_value_agg
            }
          })
        end

        it "limits `terms` aggregations based on the query `size`" do
          query = new_query(aggregations: [aggregation_query_of(name: "teams", sub_aggregations: [
            nested_sub_aggregation_of(path_in_index: ["seasons_nested"], query: sub_aggregation_query_of(
              name: "seasons_nested",
              first: 14,
              groupings: [field_term_grouping_of("seasons_nested", "year")]
            ))
          ])])

          expect(datastore_body_of(query)).to include_aggs({
            "teams:seasons_nested" => {
              "nested" => {"path" => "seasons_nested"},
              "meta" => outer_meta({"buckets_path" => ["seasons_nested.year"]}, size: 14),
              "aggs" => {
                "seasons_nested.year" => {
                  "meta" => inner_terms_meta({"grouping_fields" => ["seasons_nested.year"], "key_path" => ["key"]}),
                  "terms" => terms({"field" => "seasons_nested.year", "collect_mode" => "depth_first"}, size: 14)
                }
              }.with_missing_value_agg
            }
          })
        end

        it "limits `terms` aggregations based on the query `size`" do
          query = new_query(aggregations: [aggregation_query_of(name: "teams", sub_aggregations: [
            nested_sub_aggregation_of(path_in_index: ["seasons_nested"], query: sub_aggregation_query_of(
              name: "seasons_nested",
              first: 17,
              groupings: [
                field_term_grouping_of("seasons_nested", "year"),
                field_term_grouping_of("seasons_nested", "notes")
              ]
            ))
          ])])

          expect(datastore_body_of(query)).to include_aggs({
            "teams:seasons_nested" => {
              "nested" => {"path" => "seasons_nested"},
              "meta" => outer_meta({"buckets_path" => ["seasons_nested.year"]}, size: 17),
              "aggs" => {
                "seasons_nested.year" => {
                  "meta" => inner_terms_meta({"buckets_path" => ["seasons_nested.notes"], "grouping_fields" => ["seasons_nested.year"], "key_path" => ["key"]}),
                  "terms" => terms({"field" => "seasons_nested.year", "collect_mode" => "depth_first"}, size: 17),
                  "aggs" => {
                    "seasons_nested.notes" => {
                      "meta" => inner_terms_meta({"grouping_fields" => ["seasons_nested.notes"], "key_path" => ["key"]}),
                      "terms" => terms({"field" => "seasons_nested.notes", "collect_mode" => "depth_first"}, size: 17)
                    }
                  }.with_missing_value_agg
                }
              }.with_missing_value_agg
            }
          })
        end

        it "can group sub-aggregations on a single date field" do
          query = new_query(aggregations: [aggregation_query_of(name: "teams", sub_aggregations: [
            nested_sub_aggregation_of(path_in_index: ["seasons_nested"], query: sub_aggregation_query_of(name: "seasons_nested", groupings: [
              date_histogram_grouping_of("seasons_nested", "started_at", "year")
            ]))
          ])])

          expect(datastore_body_of(query)).to include_aggs({
            "teams:seasons_nested" => {
              "nested" => {"path" => "seasons_nested"},
              "meta" => outer_meta({"buckets_path" => ["seasons_nested.started_at"]}),
              "aggs" => {
                "seasons_nested.started_at" => {
                  "meta" => inner_date_meta({"grouping_fields" => ["seasons_nested.started_at"], "key_path" => ["key_as_string"]}),
                  "date_histogram" => {
                    "calendar_interval" => "year",
                    "field" => "seasons_nested.started_at",
                    "format" => "strict_date_time",
                    "time_zone" => "UTC",
                    "min_doc_count" => 1
                  }
                }
              }.with_missing_value_agg
            }
          })
        end

        it "uses the GraphQL query field name (instead of the `name_in_index`) for `grouping_fields` meta on date groupings" do
          query = new_query(aggregations: [aggregation_query_of(name: "teams", sub_aggregations: [
            nested_sub_aggregation_of(path_in_index: ["seasons_nested"], query: sub_aggregation_query_of(name: "seasons_nested", groupings: [
              date_histogram_grouping_of("seasons_nested", "started_at", "year", field_names_in_graphql_query: ["sea_nest", "started"])
            ]))
          ])])

          expect(datastore_body_of(query).dig(:aggs, "teams:seasons_nested", "aggs", "sea_nest.started", "meta")).to eq(
            inner_date_meta({"grouping_fields" => ["sea_nest.started"], "key_path" => ["key_as_string"]})
          )
        end

        it "uses the GraphQL query field name (instead of the `name_in_index`) for `grouping_fields` meta on date groupings" do
          query = new_query(aggregations: [aggregation_query_of(name: "teams", sub_aggregations: [
            nested_sub_aggregation_of(path_in_index: ["seasons_nested"], query: sub_aggregation_query_of(name: "seasons_nested", groupings: [
              date_histogram_grouping_of("seasons_nested", "started_at", "year")
            ]))
          ])])

          expect(datastore_body_of(query)).to include_aggs({
            "teams:seasons_nested" => {
              "nested" => {"path" => "seasons_nested"},
              "meta" => outer_meta({"buckets_path" => ["seasons_nested.started_at"]}),
              "aggs" => {
                "seasons_nested.started_at" => {
                  "meta" => inner_date_meta({"grouping_fields" => ["seasons_nested.started_at"], "key_path" => ["key_as_string"]}),
                  "date_histogram" => {
                    "calendar_interval" => "year",
                    "field" => "seasons_nested.started_at",
                    "format" => "strict_date_time",
                    "time_zone" => "UTC",
                    "min_doc_count" => 1
                  }
                }
              }.with_missing_value_agg
            }
          })
        end

        it "can group sub-aggregations on a multiple date fields" do
          query = new_query(aggregations: [aggregation_query_of(name: "teams", sub_aggregations: [
            nested_sub_aggregation_of(path_in_index: ["seasons_nested"], query: sub_aggregation_query_of(name: "seasons_nested", groupings: [
              date_histogram_grouping_of("seasons_nested", "started_at", "year"),
              date_histogram_grouping_of("seasons_nested", "won_games_at", "year")
            ]))
          ])])

          expect(datastore_body_of(query)).to include_aggs({
            "teams:seasons_nested" => {
              "nested" => {"path" => "seasons_nested"},
              "meta" => outer_meta({"buckets_path" => ["seasons_nested.started_at"]}),
              "aggs" => {
                "seasons_nested.started_at" => {
                  "meta" => inner_date_meta({"grouping_fields" => ["seasons_nested.started_at"], "buckets_path" => ["seasons_nested.won_games_at"], "key_path" => ["key_as_string"]}),
                  "date_histogram" => {
                    "calendar_interval" => "year",
                    "field" => "seasons_nested.started_at",
                    "format" => "strict_date_time",
                    "time_zone" => "UTC",
                    "min_doc_count" => 1
                  },
                  "aggs" => {
                    "seasons_nested.won_games_at" => {
                      "meta" => inner_date_meta({"grouping_fields" => ["seasons_nested.won_games_at"], "key_path" => ["key_as_string"]}),
                      "date_histogram" => {
                        "calendar_interval" => "year",
                        "field" => "seasons_nested.won_games_at",
                        "format" => "strict_date_time",
                        "time_zone" => "UTC",
                        "min_doc_count" => 1
                      }
                    }
                  }.with_missing_value_agg
                }
              }.with_missing_value_agg
            }
          })
        end

        it "can group sub-aggregations on a single non-date field and a single date field" do
          query = new_query(aggregations: [aggregation_query_of(name: "teams", sub_aggregations: [
            nested_sub_aggregation_of(path_in_index: ["seasons_nested"], query: sub_aggregation_query_of(name: "seasons_nested", groupings: [
              date_histogram_grouping_of("seasons_nested", "started_at", "year"),
              field_term_grouping_of("seasons_nested", "notes")
            ]))
          ])])

          expect(datastore_body_of(query)).to include_aggs({
            "teams:seasons_nested" => {
              "nested" => {"path" => "seasons_nested"},
              "meta" => outer_meta({"buckets_path" => ["seasons_nested.started_at"]}),
              "aggs" => {
                "seasons_nested.started_at" => {
                  "meta" => inner_date_meta({"grouping_fields" => ["seasons_nested.started_at"], "buckets_path" => ["seasons_nested.notes"], "key_path" => ["key_as_string"]}),
                  "date_histogram" => {
                    "calendar_interval" => "year",
                    "field" => "seasons_nested.started_at",
                    "format" => "strict_date_time",
                    "time_zone" => "UTC",
                    "min_doc_count" => 1
                  },
                  "aggs" => {
                    "seasons_nested.notes" => {
                      "meta" => inner_terms_meta({"grouping_fields" => ["seasons_nested.notes"], "key_path" => ["key"]}),
                      "terms" => terms({"field" => "seasons_nested.notes", "collect_mode" => "depth_first"})
                    }
                  }.with_missing_value_agg
                }
              }.with_missing_value_agg
            }
          })
        end

        it "can group sub-aggregations on multiple non-date fields and a single date field" do
          query = new_query(aggregations: [aggregation_query_of(name: "teams", sub_aggregations: [
            nested_sub_aggregation_of(path_in_index: ["seasons_nested"], query: sub_aggregation_query_of(name: "seasons_nested", groupings: [
              date_histogram_grouping_of("seasons_nested", "started_at", "year"),
              field_term_grouping_of("seasons_nested", "year"),
              field_term_grouping_of("seasons_nested", "notes")
            ]))
          ])])

          expect(datastore_body_of(query)).to include_aggs({
            "teams:seasons_nested" => {
              "nested" => {"path" => "seasons_nested"},
              "meta" => outer_meta({"buckets_path" => ["seasons_nested.started_at"]}),
              "aggs" => {
                "seasons_nested.started_at" => {
                  "meta" => inner_date_meta({"grouping_fields" => ["seasons_nested.started_at"], "buckets_path" => ["seasons_nested.year"], "key_path" => ["key_as_string"]}),
                  "date_histogram" => {
                    "calendar_interval" => "year",
                    "field" => "seasons_nested.started_at",
                    "format" => "strict_date_time",
                    "time_zone" => "UTC",
                    "min_doc_count" => 1
                  },
                  "aggs" => {
                    "seasons_nested.year" => {
                      "meta" => inner_terms_meta({"grouping_fields" => ["seasons_nested.year"], "buckets_path" => ["seasons_nested.notes"], "key_path" => ["key"]}),
                      "terms" => terms({"field" => "seasons_nested.year", "collect_mode" => "depth_first"}),
                      "aggs" => {
                        "seasons_nested.notes" => {
                          "meta" => inner_terms_meta({"grouping_fields" => ["seasons_nested.notes"], "key_path" => ["key"]}),
                          "terms" => terms({"field" => "seasons_nested.notes", "collect_mode" => "depth_first"})
                        }
                      }.with_missing_value_agg
                    }
                  }.with_missing_value_agg
                }
              }.with_missing_value_agg
            }
          })
        end

        it "can group sub-aggregations on multiple non-date fields and multiple date fields" do
          query = new_query(aggregations: [aggregation_query_of(name: "teams", sub_aggregations: [
            nested_sub_aggregation_of(path_in_index: ["seasons_nested"], query: sub_aggregation_query_of(name: "seasons_nested", groupings: [
              date_histogram_grouping_of("seasons_nested", "started_at", "year"),
              date_histogram_grouping_of("seasons_nested", "won_games_at", "year"),
              field_term_grouping_of("seasons_nested", "year"),
              field_term_grouping_of("seasons_nested", "notes")
            ]))
          ])])

          expect(datastore_body_of(query)).to include_aggs({
            "teams:seasons_nested" => {
              "nested" => {"path" => "seasons_nested"},
              "meta" => outer_meta({"buckets_path" => ["seasons_nested.started_at"]}),
              "aggs" => {
                "seasons_nested.started_at" => {
                  "meta" => inner_date_meta({"grouping_fields" => ["seasons_nested.started_at"], "buckets_path" => ["seasons_nested.won_games_at"], "key_path" => ["key_as_string"]}),
                  "date_histogram" => {
                    "calendar_interval" => "year",
                    "field" => "seasons_nested.started_at",
                    "format" => "strict_date_time",
                    "time_zone" => "UTC",
                    "min_doc_count" => 1
                  },
                  "aggs" => {
                    "seasons_nested.won_games_at" => {
                      "meta" => inner_date_meta({"grouping_fields" => ["seasons_nested.won_games_at"], "buckets_path" => ["seasons_nested.year"], "key_path" => ["key_as_string"]}),
                      "date_histogram" => {
                        "calendar_interval" => "year",
                        "field" => "seasons_nested.won_games_at",
                        "format" => "strict_date_time",
                        "time_zone" => "UTC",
                        "min_doc_count" => 1
                      },
                      "aggs" => {
                        "seasons_nested.year" => {
                          "meta" => inner_terms_meta({"grouping_fields" => ["seasons_nested.year"], "buckets_path" => ["seasons_nested.notes"], "key_path" => ["key"]}),
                          "terms" => terms({"field" => "seasons_nested.year", "collect_mode" => "depth_first"}),
                          "aggs" => {
                            "seasons_nested.notes" => {
                              "meta" => inner_terms_meta({"grouping_fields" => ["seasons_nested.notes"], "key_path" => ["key"]}),
                              "terms" => terms({"field" => "seasons_nested.notes", "collect_mode" => "depth_first"})
                            }
                          }.with_missing_value_agg
                        }
                      }.with_missing_value_agg
                    }
                  }.with_missing_value_agg
                }
              }.with_missing_value_agg
            }
          })
        end

        it "accounts for an extra filtering layer in the `buckets_path` meta" do
          query = new_query(aggregations: [aggregation_query_of(name: "teams", sub_aggregations: [
            nested_sub_aggregation_of(path_in_index: ["seasons_nested"], query: sub_aggregation_query_of(
              name: "seasons_nested",
              groupings: [field_term_grouping_of("seasons_nested", "year")],
              filter: {"year" => {"gt" => 2020}}
            ))
          ])])

          expect(datastore_body_of(query)).to include_aggs({
            "teams:seasons_nested" => {
              "nested" => {"path" => "seasons_nested"},
              "meta" => outer_meta({"buckets_path" => ["seasons_nested:filtered", "seasons_nested.year"]}),
              "aggs" => {
                "seasons_nested:filtered" => {
                  "filter" => {
                    bool: {filter: [{range: {"seasons_nested.year" => {gt: 2020}}}]}
                  },
                  "aggs" => {
                    "seasons_nested.year" => {
                      "meta" => inner_terms_meta({"grouping_fields" => ["seasons_nested.year"], "key_path" => ["key"]}),
                      "terms" => terms({"field" => "seasons_nested.year", "collect_mode" => "depth_first"})
                    }
                  }.with_missing_value_agg
                }
              }
            }
          })
        end

        it "encodes embedded grouping fields in the meta" do
          query = new_query(aggregations: [aggregation_query_of(name: "teams", sub_aggregations: [
            nested_sub_aggregation_of(path_in_index: ["seasons_nested"], query: sub_aggregation_query_of(
              name: "seasons_nested",
              groupings: [
                field_term_grouping_of("seasons_nested", "parent1", "parent2", "year"),
                date_histogram_grouping_of("seasons_nested", "parent1", "parent2", "started_at", "year")
              ]
            ))
          ])])

          date_groupings = datastore_body_of(query).dig(:aggs, "teams:seasons_nested", "aggs", "seasons_nested.parent1.parent2.started_at")

          expect(date_groupings.dig("meta", "grouping_fields")).to eq ["seasons_nested.parent1.parent2.started_at"]
          expect(date_groupings.dig("aggs", "seasons_nested.parent1.parent2.year", "meta", "grouping_fields")).to eq ["seasons_nested.parent1.parent2.year"]
        end

        it "sets `show_term_doc_count_error` based on the `needs_doc_count_error` query flag" do
          term_options_for_true, term_options_for_false = [true, false].map do |needs_doc_count_error|
            query = new_query(aggregations: [aggregation_query_of(name: "teams", sub_aggregations: [
              nested_sub_aggregation_of(path_in_index: ["seasons_nested"], query: sub_aggregation_query_of(
                name: "seasons_nested",
                needs_doc_count_error: needs_doc_count_error,
                groupings: [field_term_grouping_of("seasons_nested", "year")]
              ))
            ])])

            datastore_body_of(query).dig(:aggs, "teams:seasons_nested", "aggs", "seasons_nested.year", "terms")
          end

          expect(term_options_for_true).to include("show_term_doc_count_error" => true)
          expect(term_options_for_false).to include("show_term_doc_count_error" => false)
        end
      end

      context "with groupings (using the `CompositeGroupingAdapter`)" do
        include_context "sub-aggregation support", Aggregation::CompositeGroupingAdapter

        it "builds a `composite` sub-aggregation query" do
          query = new_query(aggregations: [aggregation_query_of(name: "teams", sub_aggregations: [
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
          ])])

          expect(datastore_body_of(query)).to include_aggs({
            "teams:seasons_nested" => {
              "meta" => outer_meta({"buckets_path" => ["seasons_nested"]}),
              "nested" => {"path" => "seasons_nested"},
              "aggs" => {
                "seasons_nested" => {
                  "composite" => {
                    "size" => 51,
                    "sources" => [
                      {
                        "seasons_nested.started_at" => {
                          "date_histogram" => {
                            "calendar_interval" => "year",
                            "missing_bucket" => true,
                            "field" => "seasons_nested.started_at",
                            "format" => "strict_date_time",
                            "time_zone" => "UTC"
                          }
                        }
                      },
                      {
                        "seasons_nested.year" => {
                          "terms" => {
                            "field" => "seasons_nested.year",
                            "missing_bucket" => true
                          }
                        }
                      },
                      {
                        "seasons_nested.notes" => {
                          "terms" => {
                            "field" => "seasons_nested.notes",
                            "missing_bucket" => true
                          }
                        }
                      }
                    ]
                  },
                  "aggs" => {
                    "seasons_nested:seasons_nested.year:exact_min" => {
                      "min" => {"field" => "seasons_nested.year"}
                    },
                    "seasons_nested:seasons_nested.the_record.win_count:exact_max" => {
                      "max" => {"field" => "seasons_nested.the_record.win_count"}
                    },
                    "seasons_nested:seasons_nested.the_record.win_count:approximate_avg" => {
                      "avg" => {"field" => "seasons_nested.the_record.win_count"}
                    }
                  }
                }
              }
            }
          })
        end

        it "uses the GraphQL query field names in composite aggregation keys when they differ from the field names in the index" do
          query = new_query(aggregations: [aggregation_query_of(name: "teams", sub_aggregations: [
            nested_sub_aggregation_of(path_in_index: ["seasons_nested"], query: sub_aggregation_query_of(
              name: "seasons_nested",
              needs_doc_count: true,
              groupings: [
                date_histogram_grouping_of("seasons_nested", "started_at", "year", field_names_in_graphql_query: ["sea_nest", "started"]),
                field_term_grouping_of("seasons_nested", "year", field_names_in_graphql_query: ["sea_nest", "the_year"]),
                field_term_grouping_of("seasons_nested", "notes", field_names_in_graphql_query: ["sea_nest", "note"])
              ]
            ))
          ])])

          sources = datastore_body_of(query).dig(:aggs, "teams:seasons_nested", "aggs", "seasons_nested", "composite", "sources")
          expect(sources).to eq [
            {
              "sea_nest.started" => {
                "date_histogram" => {
                  "calendar_interval" => "year",
                  "missing_bucket" => true,
                  "field" => "seasons_nested.started_at",
                  "format" => "strict_date_time",
                  "time_zone" => "UTC"
                }
              }
            },
            {
              "sea_nest.the_year" => {
                "terms" => {
                  "field" => "seasons_nested.year",
                  "missing_bucket" => true
                }
              }
            },
            {
              "sea_nest.note" => {
                "terms" => {
                  "field" => "seasons_nested.notes",
                  "missing_bucket" => true
                }
              }
            }
          ]
        end
      end

      def include_aggs(aggs)
        include(aggs: aggs)
      end

      def exclude_aggs
        exclude(:aggs)
      end

      def terms(terms_hash, size: 50, show_term_doc_count_error: false)
        # We add 1 to the size because we ask for one more from the datastore to detect `page_info.has_next_page`.
        terms_hash.merge({"size" => size + 1, "show_term_doc_count_error" => show_term_doc_count_error})
      end
    end
  end
end
