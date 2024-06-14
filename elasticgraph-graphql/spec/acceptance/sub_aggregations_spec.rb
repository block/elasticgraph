# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphql/aggregation/composite_grouping_adapter"
require "elastic_graph/graphql/aggregation/non_composite_grouping_adapter"
require_relative "elasticgraph_graphql_acceptance_support"

module ElasticGraph
  RSpec.describe "ElasticGraph::GraphQL--sub-aggregations" do
    include_context "ElasticGraph GraphQL acceptance aggregation support"

    with_both_casing_forms do
      shared_examples_for "sub-aggregation acceptance" do
        it "returns the expected empty responses when the indices have not been configured or no documents have yet been indexed", :expect_search_routing do
          main_datastore_client.delete_indices("team*")

          expect_indices_not_configured_error { aggregate_teams_grouped_by_league(allow_errors: true) }
          expect_indices_not_configured_error { aggregate_sibling_and_deeply_nested_counts(allow_errors: true) }
          expect_indices_not_configured_error { aggregate_season_counts_grouped_by("year", "note", allow_errors: true) }

          # Reconfigure the indices (but don't index any docs)
          admin.cluster_configurator.configure_cluster(StringIO.new)

          # Note: this is technically a "root" aggregations query (not sub-aggregations), but it's another case we need to
          # exercise when no documents have yet been indexed. So we're including it here.
          teams_grouped_by_league = aggregate_teams_grouped_by_league
          expect(teams_grouped_by_league).to eq []

          player_count, season_count, season_player_count, season_player_season_count = aggregate_sibling_and_deeply_nested_counts
          expect(player_count).to eq(count_detail_of(0))
          expect(season_count).to eq(count_detail_of(0))
          expect(season_player_count).to eq(count_detail_of(0))
          expect(season_player_season_count).to eq(count_detail_of(0))

          team_seasons_nodes = aggregate_season_counts_grouped_by("year", "note")
          expect(indexed_counts_from(team_seasons_nodes)).to eq({})
        end

        it "supports arbitrarily deeply nested sub-aggregations", :expect_search_routing, :expect_index_exclusions do
          index_data
          test_ungrouped_sub_aggregations
          test_grouped_sub_aggregations
        end

        def index_data
          index_records(
            build(
              :team,
              current_name: "Yankees",
              current_players: [build(:player, name: "Bob")],
              formed_on: "1903-01-01",
              seasons: [
                build(:team_season, year: 2020, was_shortened: true, record: build(:team_record, wins: 50, losses: 12, first_win_on: "2020-03-02", last_win_on: "2020-11-12"), notes: ["pandemic", "shortened"], started_at: "2020-01-15T12:02:20Z", players: [
                  build(:player, name: "Ted", seasons: [build(:player_season, year: 2018, games_played: 20), build(:player_season, year: 2018, games_played: 30)]),
                  build(:player, name: "Dave", seasons: [build(:player_season, year: 2022, games_played: 10)])
                ])
              ]
            ),
            build(
              :team,
              current_name: "Dodgers",
              formed_on: "1883-01-01",
              current_players: [build(:player, name: "Kat", seasons: []), build(:player, name: "Sue", seasons: [])],
              seasons: [
                build(:team_season, year: 2020, was_shortened: true, record: build(:team_record, wins: 30, losses: 22, first_win_on: "2020-05-02", last_win_on: "2020-12-12"), notes: ["pandemic", "covid"], started_at: "2020-01-15T12:02:20Z", players: []),
                build(:team_season, year: 2021, was_shortened: false, record: build(:team_record, wins: nil, losses: 22, first_win_on: nil, last_win_on: "2021-12-12"), notes: [], started_at: "2021-02-16T13:03:30Z", players: []),
                build(:team_season, year: 2022, was_shortened: false, record: build(:team_record, wins: 40, losses: 15, first_win_on: "2022-06-02", last_win_on: "2022-08-12"), notes: [], started_at: "2022-03-17T14:04:40Z", players: []),
                build(:team_season, year: 2023, was_shortened: false, record: build(:team_record, wins: 50, losses: nil, first_win_on: "2023-01-06", last_win_on: nil), notes: [], started_at: "2023-04-18T12:02:59Z", players: [])
              ]
            ),
            build(
              :team,
              current_name: "Red Sox",
              formed_on: "1901-01-01",
              current_players: [build(:player, name: "Ed", seasons: []), build(:player, name: "Ty", seasons: [])],
              seasons: [
                build(:team_season, year: 2019, was_shortened: false, record: build(:team_record, wins: 40, losses: 7, first_win_on: "2019-04-02", last_win_on: "2019-07-12"), notes: ["old rules"], started_at: "2019-01-15T12:02:20Z", players: [])
              ]
            ),
            build(
              :team,
              current_name: "Magenta Sox",
              formed_on: "1921-01-01",
              current_players: [],
              seasons: []
            )
          )

          # Ensure the cached `known_related_query_rollover_indices` is up-to-date with any new indices created by indexing these docs.
          pre_cache_index_state(graphql)
        end

        def test_ungrouped_sub_aggregations
          # Demonstrate a successful empty result when we filter to no shard routing values.
          seasons, seasons_player_seasons = count_seasons_and_season_player_seasons(team_aggregations: {filter: {league: {equal_to_any_of: []}}})
          expect(seasons).to eq(count_detail_of(0))
          expect(seasons_player_seasons).to eq(count_detail_of(0))

          # Demonstrate a successful empty result when our rollover field filter excludes all values.
          seasons, seasons_player_seasons = count_seasons_and_season_player_seasons(team_aggregations: {filter: {formed_on: {equal_to_any_of: []}}})
          expect(seasons).to eq(count_detail_of(0))
          expect(seasons_player_seasons).to eq(count_detail_of(0))

          # Demonstrate a successful empty result when our rollover field filter only includes values outside the ranges of our indices.
          seasons, seasons_player_seasons = count_seasons_and_season_player_seasons(team_aggregations: {filter: {formed_on: {gt: "7890-01-01"}}})
          expect(seasons).to eq(count_detail_of(0))
          expect(seasons_player_seasons).to eq(count_detail_of(0))

          player_count, season_count, season_player_count, season_player_season_count = aggregate_sibling_and_deeply_nested_counts
          expect(player_count).to eq(count_detail_of(5))
          expect(season_count).to eq(count_detail_of(6))
          expect(season_player_count).to eq(count_detail_of(2))
          expect(season_player_season_count).to eq(count_detail_of(3))

          player_count, season_count = aggregate_count_under_extra_object_layer
          expect(player_count).to eq(count_detail_of(5))
          expect(season_count).to eq(count_detail_of(6))

          seasons_before_2021, seasons_before_2021_player_seasons = count_seasons_and_season_player_seasons(
            seasons: {filter: {year: {lt: 2021}}}
          )
          expect(seasons_before_2021).to eq(count_detail_of(3))
          expect(seasons_before_2021_player_seasons).to eq(count_detail_of(3))

          seasons_after_2019, seasons_after_2019_player_seasons_before_2020 = count_seasons_and_season_player_seasons(
            seasons: {filter: {year: {gt: 2019}}},
            season_player_seasons: {filter: {year: {lt: 2020}}}
          )
          expect(seasons_after_2019).to eq(count_detail_of(5))
          expect(seasons_after_2019_player_seasons_before_2020).to eq(count_detail_of(2))

          seasons_after_2019, seasons_after_2019_player_seasons_before_2020 = count_seasons_and_season_player_seasons(
            seasons: {filter: {year: {gt: nil}}},
            season_player_seasons: {filter: {year: {lt: nil}}}
          )
          expect(seasons_after_2019).to eq(count_detail_of(6))
          expect(seasons_after_2019_player_seasons_before_2020).to eq(count_detail_of(3))

          # Test that aliases work as expected with sub-aggregations
          verify_sub_aggregations_with_aliases

          # Test `first: positive-value` arg on an ungrouped sub-aggregation
          seasons, season_player_seasons = count_seasons_and_season_player_seasons(
            seasons: {first: 1},
            season_player_seasons: {first: 1}
          )
          expect(seasons).to eq(count_detail_of(6))
          expect(season_player_seasons).to eq(count_detail_of(3))

          # Test `first: 0` arg on an ungrouped sub-aggregation
          seasons, season_player_seasons = count_seasons_and_season_player_seasons(
            seasons: {first: 0},
            season_player_seasons: {first: 0}
          )
          expect(seasons).to eq(nil)
          expect(season_player_seasons).to eq(nil)
        end

        def test_grouped_sub_aggregations
          # Demonstrate a successful empty result when we filter to no documents.
          team_seasons_nodes = aggregate_season_counts_grouped_by("year", team_aggregations_args: {filter: {current_name: {equal_to_any_of: [nil]}}})
          expect(team_seasons_nodes).to eq([])

          # Demonstrate a successful empty result when we filter to no shard routing values.
          team_seasons_nodes = aggregate_season_counts_grouped_by("year", team_aggregations_args: {filter: {league: {equal_to_any_of: []}}})
          expect(team_seasons_nodes).to eq([])

          # Demonstrate a successful empty result when our rollover field filter excludes all values.
          team_seasons_nodes = aggregate_season_counts_grouped_by("year", team_aggregations_args: {filter: {formed_on: {equal_to_any_of: []}}})
          expect(team_seasons_nodes).to eq([])

          # Demonstrate a successful empty result when our rollover field filter only includes values outside the ranges of our indices.
          team_seasons_nodes = aggregate_season_counts_grouped_by("year", team_aggregations_args: {filter: {formed_on: {gt: "7890-01-01"}}})
          expect(team_seasons_nodes).to eq([])

          # Test a simple sub-aggregation grouping of one `terms` field
          team_seasons_nodes = aggregate_season_counts_grouped_by("year")
          expect(indexed_counts_from(team_seasons_nodes)).to eq({
            {"year" => 2019} => count_detail_of(1),
            {"year" => 2020} => count_detail_of(2),
            {"year" => 2021} => count_detail_of(1),
            {"year" => 2022} => count_detail_of(1),
            {"year" => 2023} => count_detail_of(1)
          })

          # Test a simple sub-aggregation grouping of one Boolean `terms` field
          team_seasons_nodes = aggregate_season_counts_grouped_by("was_shortened")
          expect(indexed_counts_from(team_seasons_nodes)).to eq({
            {case_correctly("was_shortened") => true} => count_detail_of(2),
            {case_correctly("was_shortened") => false} => count_detail_of(4)
          })

          # Test what happens if all grouped by fields are excluded via a directive.
          team_seasons_nodes = aggregate_season_counts_grouped_by("year @include(if: false)", "note @skip(if: true)")
          expect(indexed_counts_from(team_seasons_nodes)).to eq({
            {} => count_detail_of(6)
          })

          # Test applying a filter on the rollover `Date` field.
          team_seasons_nodes = aggregate_season_counts_grouped_by("year", team_aggregations_args: {filter: {formed_on: {gt: "1900-01-01"}}})
          expect(indexed_counts_from(team_seasons_nodes)).to eq({
            {"year" => 2019} => count_detail_of(1),
            {"year" => 2020} => count_detail_of(1)
          })
          expect_to_have_excluded_indices("main", [index_definition_name_for("teams_rollover__1883")])

          # Test a sub-aggregation grouping of two `terms` field
          team_seasons_nodes = aggregate_season_counts_grouped_by("year", "note")
          expect(indexed_counts_from(team_seasons_nodes)).to eq({
            {"year" => 2020, "note" => "covid"} => count_detail_of(1),
            {"year" => 2019, "note" => "old rules"} => count_detail_of(1),
            {"year" => 2020, "note" => "pandemic"} => count_detail_of(2),
            {"year" => 2020, "note" => "shortened"} => count_detail_of(1),
            {"year" => 2021, "note" => nil} => count_detail_of(1),
            {"year" => 2022, "note" => nil} => count_detail_of(1),
            {"year" => 2023, "note" => nil} => count_detail_of(1)
          })

          verify_filtered_sub_aggregations_with_grouped_by

          # Group on some date fields (with no term grouping).
          team_seasons_nodes = aggregate_season_counts_grouped_by("record { last_win_on { as_date(truncation_unit: MONTH) }, first_win_on { as_date(truncation_unit: MONTH) }}")
          expect(indexed_counts_from(team_seasons_nodes)).to eq({
            {"record" => {case_correctly("first_win_on") => {case_correctly("as_date") => "2019-04-01"}, case_correctly("last_win_on") => {case_correctly("as_date") => "2019-07-01"}}} => count_detail_of(1),
            {"record" => {case_correctly("first_win_on") => {case_correctly("as_date") => "2020-03-01"}, case_correctly("last_win_on") => {case_correctly("as_date") => "2020-11-01"}}} => count_detail_of(1),
            {"record" => {case_correctly("first_win_on") => {case_correctly("as_date") => "2020-05-01"}, case_correctly("last_win_on") => {case_correctly("as_date") => "2020-12-01"}}} => count_detail_of(1),
            {"record" => {case_correctly("first_win_on") => {case_correctly("as_date") => "2022-06-01"}, case_correctly("last_win_on") => {case_correctly("as_date") => "2022-08-01"}}} => count_detail_of(1),
            {"record" => {case_correctly("first_win_on") => {case_correctly("as_date") => "2023-01-01"}, case_correctly("last_win_on") => {case_correctly("as_date") => nil}}} => count_detail_of(1),
            {"record" => {case_correctly("first_win_on") => {case_correctly("as_date") => nil}, case_correctly("last_win_on") => {case_correctly("as_date") => "2021-12-01"}}} => count_detail_of(1)
          })

          # Group on sub-fields of an object, some date fields, and some fields with alternate `name_in_index`.
          team_seasons_nodes = aggregate_season_counts_grouped_by("record { wins, last_win_on { as_date(truncation_unit: MONTH) }, first_win_on { as_date(truncation_unit: MONTH) }}")
          expect(indexed_counts_from(team_seasons_nodes)).to eq({
            {"record" => {case_correctly("first_win_on") => {case_correctly("as_date") => "2019-04-01"}, case_correctly("last_win_on") => {case_correctly("as_date") => "2019-07-01"}, "wins" => 40}} => count_detail_of(1),
            {"record" => {case_correctly("first_win_on") => {case_correctly("as_date") => "2020-03-01"}, case_correctly("last_win_on") => {case_correctly("as_date") => "2020-11-01"}, "wins" => 50}} => count_detail_of(1),
            {"record" => {case_correctly("first_win_on") => {case_correctly("as_date") => "2020-05-01"}, case_correctly("last_win_on") => {case_correctly("as_date") => "2020-12-01"}, "wins" => 30}} => count_detail_of(1),
            {"record" => {case_correctly("first_win_on") => {case_correctly("as_date") => "2022-06-01"}, case_correctly("last_win_on") => {case_correctly("as_date") => "2022-08-01"}, "wins" => 40}} => count_detail_of(1),
            {"record" => {case_correctly("first_win_on") => {case_correctly("as_date") => "2023-01-01"}, case_correctly("last_win_on") => {case_correctly("as_date") => nil}, "wins" => 50}} => count_detail_of(1),
            {"record" => {case_correctly("first_win_on") => {case_correctly("as_date") => nil}, case_correctly("last_win_on") => {case_correctly("as_date") => "2021-12-01"}, "wins" => nil}} => count_detail_of(1)
          })

          # Test using groupings on sibling and deeply nested sub-aggs.
          verify_aggregate_sibling_and_deeply_nested_grouped_counts_and_aggregated_values

          # Test `first: positive-value` arg on a grouped sub-aggregation (single term)
          team_seasons_nodes = aggregate_season_counts_grouped_by("year", first: 2, seasons_has_next_page: true)
          expect(indexed_counts_from(team_seasons_nodes)).to eq({
            {"year" => 2020} => count_detail_of(2),
            {"year" => 2019} => count_detail_of(1)
          })

          # Test `first: positive-value` arg on a grouped sub-aggregation (multiple terms)
          team_seasons_nodes = aggregate_season_counts_grouped_by("year", "note", first: 2, seasons_has_next_page: true)
          expect(indexed_counts_from(team_seasons_nodes)).to eq(first_two_counts_grouped_by_year_and_note)

          # Test `first: positive-value` arg on a grouped sub-aggregation (single term + multiple date fields)
          team_seasons_nodes = aggregate_season_counts_grouped_by("record { wins, last_win_on { as_date(truncation_unit: MONTH) }, first_win_on { as_date(truncation_unit: MONTH) }}", first: 2, seasons_has_next_page: true)
          expect(indexed_counts_from(team_seasons_nodes)).to eq(first_two_counts_grouped_by_wins_last_win_on_month_first_win_on_month)

          # Test `first: 0` arg on a grouped sub-aggregation (single term)
          team_seasons_nodes = aggregate_season_counts_grouped_by("year", first: 0)
          expect(team_seasons_nodes).to eq []

          # Test `first: 0` arg on a grouped sub-aggregation (multiple terms)
          team_seasons_nodes = aggregate_season_counts_grouped_by("year", "note", first: 0)
          expect(team_seasons_nodes).to eq []

          # Test `first: 0` arg on a grouped sub-aggregation (single term + multiple date fields)
          team_seasons_nodes = aggregate_season_counts_grouped_by("record { wins, last_win_on { as_date(truncation_unit: MONTH) }, first_win_on { as_date(truncation_unit: MONTH) }}", first: 0)
          expect(team_seasons_nodes).to eq []

          # Verify date/time aggregations
          # DateTime:as_date_time()
          team_seasons_nodes = aggregate_season_counts_grouped_by("started_at {as_date_time(truncation_unit: DAY)}")
          expect(indexed_counts_from(team_seasons_nodes)).to eq({
            {case_correctly("started_at") => {case_correctly("as_date_time") => "2019-01-15T00:00:00.000Z"}} => count_detail_of(1),
            {case_correctly("started_at") => {case_correctly("as_date_time") => "2020-01-15T00:00:00.000Z"}} => count_detail_of(2),
            {case_correctly("started_at") => {case_correctly("as_date_time") => "2021-02-16T00:00:00.000Z"}} => count_detail_of(1),
            {case_correctly("started_at") => {case_correctly("as_date_time") => "2022-03-17T00:00:00.000Z"}} => count_detail_of(1),
            {case_correctly("started_at") => {case_correctly("as_date_time") => "2023-04-18T00:00:00.000Z"}} => count_detail_of(1)
          })

          # DateTime: as_date()
          team_seasons_nodes = aggregate_season_counts_grouped_by("started_at {as_date(truncation_unit: MONTH)}")
          expect(indexed_counts_from(team_seasons_nodes)).to eq({
            {case_correctly("started_at") => {case_correctly("as_date") => "2019-01-01"}} => count_detail_of(1),
            {case_correctly("started_at") => {case_correctly("as_date") => "2020-01-01"}} => count_detail_of(2),
            {case_correctly("started_at") => {case_correctly("as_date") => "2021-02-01"}} => count_detail_of(1),
            {case_correctly("started_at") => {case_correctly("as_date") => "2022-03-01"}} => count_detail_of(1),
            {case_correctly("started_at") => {case_correctly("as_date") => "2023-04-01"}} => count_detail_of(1)
          })

          # DateTime: as_day_of_week()
          team_seasons_nodes = aggregate_season_counts_grouped_by("started_at {as_day_of_week}")
          expect(indexed_counts_from(team_seasons_nodes)).to eq({
            {case_correctly("started_at") => {case_correctly("as_day_of_week") => enum_value("TUESDAY")}} => count_detail_of(3),
            {case_correctly("started_at") => {case_correctly("as_day_of_week") => enum_value("WEDNESDAY")}} => count_detail_of(2),
            {case_correctly("started_at") => {case_correctly("as_day_of_week") => enum_value("THURSDAY")}} => count_detail_of(1)
          })

          # DateTime: as_time_of_day() truncated to SECOND
          team_seasons_nodes = aggregate_season_counts_grouped_by("started_at {as_time_of_day(truncation_unit: SECOND)}")
          expect(indexed_counts_from(team_seasons_nodes)).to eq({
            {case_correctly("started_at") => {case_correctly("as_time_of_day") => "12:02:20"}} => count_detail_of(3),
            {case_correctly("started_at") => {case_correctly("as_time_of_day") => "12:02:59"}} => count_detail_of(1),
            {case_correctly("started_at") => {case_correctly("as_time_of_day") => "13:03:30"}} => count_detail_of(1),
            {case_correctly("started_at") => {case_correctly("as_time_of_day") => "14:04:40"}} => count_detail_of(1)
          })

          # DateTime: as_time_of_day() truncated to MINUTE
          team_seasons_nodes = aggregate_season_counts_grouped_by("started_at {as_time_of_day(truncation_unit: MINUTE)}")
          expect(indexed_counts_from(team_seasons_nodes)).to eq({
            {case_correctly("started_at") => {case_correctly("as_time_of_day") => "12:02:00"}} => count_detail_of(4),
            {case_correctly("started_at") => {case_correctly("as_time_of_day") => "13:03:00"}} => count_detail_of(1),
            {case_correctly("started_at") => {case_correctly("as_time_of_day") => "14:04:00"}} => count_detail_of(1)
          })

          # DateTime: as_time_of_day() truncated to HOUR
          team_seasons_nodes = aggregate_season_counts_grouped_by("started_at {as_time_of_day(truncation_unit: HOUR)}")
          expect(indexed_counts_from(team_seasons_nodes)).to eq({
            {case_correctly("started_at") => {case_correctly("as_time_of_day") => "12:00:00"}} => count_detail_of(4),
            {case_correctly("started_at") => {case_correctly("as_time_of_day") => "13:00:00"}} => count_detail_of(1),
            {case_correctly("started_at") => {case_correctly("as_time_of_day") => "14:00:00"}} => count_detail_of(1)
          })

          # Date: as_date()
          team_seasons_nodes = aggregate_season_counts_grouped_by("record {last_win_on {as_date(truncation_unit: MONTH)}}")
          expect(indexed_counts_from(team_seasons_nodes)).to eq({
            {"record" => {case_correctly("last_win_on") => {case_correctly("as_date") => "2019-07-01"}}} => count_detail_of(1),
            {"record" => {case_correctly("last_win_on") => {case_correctly("as_date") => "2020-11-01"}}} => count_detail_of(1),
            {"record" => {case_correctly("last_win_on") => {case_correctly("as_date") => "2020-12-01"}}} => count_detail_of(1),
            {"record" => {case_correctly("last_win_on") => {case_correctly("as_date") => "2022-08-01"}}} => count_detail_of(1),
            {"record" => {case_correctly("last_win_on") => {case_correctly("as_date") => nil}}} => count_detail_of(1),
            {"record" => {case_correctly("last_win_on") => {case_correctly("as_date") => "2021-12-01"}}} => count_detail_of(1)
          })

          # Date: as_day_of_week()
          team_seasons_nodes = aggregate_season_counts_grouped_by("record {last_win_on {as_day_of_week}}")
          expect(indexed_counts_from(team_seasons_nodes)).to eq({
            {"record" => {case_correctly("last_win_on") => {case_correctly("as_day_of_week") => enum_value("THURSDAY")}}} => count_detail_of(1),
            {"record" => {case_correctly("last_win_on") => {case_correctly("as_day_of_week") => enum_value("FRIDAY")}}} => count_detail_of(2),
            {"record" => {case_correctly("last_win_on") => {case_correctly("as_day_of_week") => enum_value("SATURDAY")}}} => count_detail_of(1),
            {"record" => {case_correctly("last_win_on") => {case_correctly("as_day_of_week") => enum_value("SUNDAY")}}} => count_detail_of(1),
            {"record" => {case_correctly("last_win_on") => {case_correctly("as_day_of_week") => nil}}} => count_detail_of(1)
          })

          test_optimizable_aggregations_with_sub_aggregations
          verify_2_subaggregations_on_same_field_under_different_parent_fields

          # Demonstrate that we can group subaggregations by fields that have a mixture of types with some `null` values mixed it.
          # (At one point this lead to an exception).
          team_seasons_nodes = aggregate_season_counts_grouped_by("note, record { losses}")
          expect(team_seasons_nodes.map { |n| n.fetch(case_correctly("grouped_by")) }).to include(
            {"note" => nil, "record" => {"losses" => nil}},
            {"note" => nil, "record" => {"losses" => 15}},
            {"note" => "covid", "record" => {"losses" => 22}}
          )
        end
      end

      context "when sub-aggregations use the `CompositeGroupingAdapter`" do
        include_examples "sub-aggregation acceptance"

        def build_graphql(**options)
          super(
            sub_aggregation_grouping_adapter: GraphQL::Aggregation::CompositeGroupingAdapter,
            **options
          )
        end

        # This part of the test involves using groupings at two levels. That results in `composite` being used
        # under `composite`, but Elasticsearch and OpenSearch return an error in that case (see below). Long term,
        # we hope to find a solution for this.
        def verify_aggregate_sibling_and_deeply_nested_grouped_counts_and_aggregated_values
          error_msg = a_string_including("[composite] aggregation cannot be used with a parent aggregation of type: [CompositeAggregationFactory]")

          expect {
            super
          }.to raise_error(Errors::SearchFailedError, error_msg).and log_warning(error_msg)
        end

        # Likewise, OpenSearch can't handle a composite agg under a filter agg, until they release this fix:
        # https://github.com/opensearch-project/OpenSearch/pull/11499
        #
        # ...but this works on Elasticsearch, and now works on OpenSearch 2.13+.
        def verify_filtered_sub_aggregations_with_grouped_by
          # :nocov: -- only one side of this conditional is covered in any given test suite run.
          return super if datastore_backend == :elasticsearch
          return super if ::Gem::Version.new(datastore_version) >= ::Gem::Version.new("2.13.0")

          error_msg = a_string_including("[composite] aggregation cannot be used with a parent aggregation of type: [FilterAggregatorFactory]")

          expect {
            super
          }.to raise_error(Errors::SearchFailedError, error_msg).and log_warning(error_msg)
          # :nocov:
        end

        # When the `CompositeGroupingAdapter` is used, aggregation groupings are sorted by the fields
        # we group on. This results in a different first 2 from the `NonCompositeGroupingAdapter` case.
        let(:first_two_counts_grouped_by_year_and_note) do
          {
            {"year" => 2019, "note" => "old rules"} => count_detail_of(1),
            {"year" => 2020, "note" => "covid"} => count_detail_of(1)
          }
        end
        let(:first_two_counts_grouped_by_wins_last_win_on_month_first_win_on_month) do
          {
            {"record" => {case_correctly("first_win_on") => {case_correctly("as_date") => nil}, case_correctly("last_win_on") => {case_correctly("as_date") => "2021-12-01"}, "wins" => nil}} => count_detail_of(1),
            {"record" => {case_correctly("first_win_on") => {case_correctly("as_date") => "2020-05-01"}, case_correctly("last_win_on") => {case_correctly("as_date") => "2020-12-01"}, "wins" => 30}} => count_detail_of(1)
          }
        end
      end

      context "when sub-aggregations use the `NonCompositeGroupingAdapter`" do
        include_examples "sub-aggregation acceptance"

        def build_graphql(**options)
          super(
            sub_aggregation_grouping_adapter: GraphQL::Aggregation::NonCompositeGroupingAdapter,
            **options
          )
        end

        # When the `NonCompositeGroupingAdapter` is used, aggregation groupings are sorted desc by the
        # counts. This results in a different first 2 from the `CompositeGroupingAdapter` case.
        let(:first_two_counts_grouped_by_year_and_note) do
          {
            {"year" => 2020, "note" => "pandemic"} => count_detail_of(2),
            {"year" => 2019, "note" => "old rules"} => count_detail_of(1)
          }
        end
        let(:first_two_counts_grouped_by_wins_last_win_on_month_first_win_on_month) do
          {
            {"record" => {case_correctly("first_win_on") => {case_correctly("as_date") => "2019-04-01"}, case_correctly("last_win_on") => {case_correctly("as_date") => "2019-07-01"}, "wins" => 40}} => count_detail_of(1),
            {"record" => {case_correctly("first_win_on") => {case_correctly("as_date") => "2020-03-01"}, case_correctly("last_win_on") => {case_correctly("as_date") => "2020-11-01"}, "wins" => 50}} => count_detail_of(1)
          }
        end
      end

      let(:page_info_snippet) do
        <<~EOS
          page_info {
            has_next_page
            has_previous_page
            start_cursor
            end_cursor
          }
        EOS
      end

      def aggregate_sibling_and_deeply_nested_counts(allow_errors: false)
        response = call_graphql_query(<<~EOS, allow_errors: allow_errors)
          query {
            team_aggregations {
              #{page_info_snippet}
              nodes {
                sub_aggregations {
                  current_players_nested {
                    #{page_info_snippet}
                    nodes {
                      count_detail {
                        ...count_aggregations
                      }
                    }
                  }

                  seasons_nested {
                    #{page_info_snippet}
                    nodes {
                      count_detail {
                        ...count_aggregations
                      }

                      sub_aggregations {
                        players_nested {
                          #{page_info_snippet}
                          nodes {
                            count_detail {
                              ...count_aggregations
                            }

                            sub_aggregations {
                              seasons_nested {
                                #{page_info_snippet}
                                nodes {
                                  count_detail {
                                    ...count_aggregations
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
            }
          }

          fragment count_aggregations on AggregationCountDetail {
            approximate_value
            exact_value
            upper_bound
          }
        EOS

        return response if allow_errors

        team_node = get_single_aggregations_node_from(response, "team_aggregations", parent_field_name: "data")
        player_node = get_single_aggregations_node_from(team_node, "current_players_nested")
        season_node = get_single_aggregations_node_from(team_node, "seasons_nested")
        season_player_node = get_single_aggregations_node_from(season_node, "players_nested")
        season_player_season_node = get_single_aggregations_node_from(season_player_node, "seasons_nested")

        [
          player_node.fetch(case_correctly("count_detail")),
          season_node.fetch(case_correctly("count_detail")),
          season_player_node.fetch(case_correctly("count_detail")),
          season_player_season_node.fetch(case_correctly("count_detail"))
        ]
      end

      def verify_filtered_sub_aggregations_with_grouped_by
        team_seasons_nodes = aggregate_season_counts_grouped_by("year", filter: {year: {lt: 2021}})
        expect(indexed_counts_from(team_seasons_nodes)).to eq({
          {"year" => 2019} => count_detail_of(1),
          {"year" => 2020} => count_detail_of(2)
        })
      end

      def verify_2_subaggregations_on_same_field_under_different_parent_fields
        team_aggs = call_graphql_query(<<~EOS).dig("data", case_correctly("team_aggregations"))
          query {
            team_aggregations {
              nodes {
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
              }
            }
          }
        EOS

        expected_nested_fields_value = {"seasons" => {
          "nodes" => [{
            case_correctly("aggregated_values") => {
              "year" => {case_correctly("exact_min") => 2019}
            }
          }]
        }}

        expect(team_aggs).to eq({
          "nodes" => [{
            case_correctly("sub_aggregations") => {
              case_correctly("nested_fields") => expected_nested_fields_value,
              case_correctly("nested_fields2") => expected_nested_fields_value
            }
          }]
        })
      end

      def verify_aggregate_sibling_and_deeply_nested_grouped_counts_and_aggregated_values
        team_aggs = call_graphql_query(<<~EOS).dig("data", case_correctly("team_aggregations"))
          query {
            team_aggregations {
              nodes {
                sub_aggregations {
                  current_players_nested {
                    nodes {
                      grouped_by { name }
                      count_detail { approximate_value }
                      aggregated_values { name { approximate_distinct_value_count } }
                    }
                  }

                  seasons_nested {
                    nodes {
                      grouped_by { year }
                      count_detail { approximate_value }
                      aggregated_values { record { wins { approximate_avg, exact_max } } }

                      sub_aggregations {
                        players_nested {
                          nodes {
                            grouped_by { name }
                            count_detail { approximate_value }
                            aggregated_values { name { approximate_distinct_value_count } }

                            sub_aggregations {
                              seasons_nested {
                                nodes {
                                  grouped_by { year }
                                  count_detail { approximate_value }
                                  aggregated_values { games_played { exact_max } }
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
          }
        EOS

        expect(team_aggs).to eq({
          case_correctly("nodes") => [
            {
              case_correctly("sub_aggregations") => {
                case_correctly("current_players_nested") => {
                  case_correctly("nodes") => [
                    {
                      case_correctly("grouped_by") => {case_correctly("name") => "Bob"},
                      case_correctly(case_correctly("count_detail")) => {case_correctly("approximate_value") => 1},
                      case_correctly("aggregated_values") => {"name" => {case_correctly("approximate_distinct_value_count") => 1}}
                    },
                    {
                      case_correctly("grouped_by") => {case_correctly("name") => "Ed"},
                      case_correctly(case_correctly("count_detail")) => {case_correctly("approximate_value") => 1},
                      case_correctly("aggregated_values") => {"name" => {case_correctly("approximate_distinct_value_count") => 1}}
                    },
                    {
                      case_correctly("grouped_by") => {case_correctly("name") => "Kat"},
                      case_correctly(case_correctly("count_detail")) => {case_correctly("approximate_value") => 1},
                      case_correctly("aggregated_values") => {"name" => {case_correctly("approximate_distinct_value_count") => 1}}
                    },
                    {
                      case_correctly("grouped_by") => {case_correctly("name") => "Sue"},
                      case_correctly(case_correctly("count_detail")) => {case_correctly("approximate_value") => 1},
                      case_correctly("aggregated_values") => {"name" => {case_correctly("approximate_distinct_value_count") => 1}}
                    },
                    {
                      case_correctly("grouped_by") => {case_correctly("name") => "Ty"},
                      case_correctly(case_correctly("count_detail")) => {case_correctly("approximate_value") => 1},
                      case_correctly("aggregated_values") => {"name" => {case_correctly("approximate_distinct_value_count") => 1}}
                    }
                  ]
                },
                case_correctly("seasons_nested") => {
                  case_correctly("nodes") => [
                    {
                      case_correctly("grouped_by") => {case_correctly("year") => 2020},
                      case_correctly(case_correctly("count_detail")) => {case_correctly("approximate_value") => 2},
                      case_correctly("aggregated_values") => {
                        "record" => {"wins" => {
                          case_correctly("approximate_avg") => 40.0,
                          case_correctly("exact_max") => 50
                        }}
                      },
                      case_correctly("sub_aggregations") => {
                        case_correctly("players_nested") => {
                          case_correctly("nodes") => [
                            {
                              case_correctly("grouped_by") => {case_correctly("name") => "Dave"},
                              case_correctly(case_correctly("count_detail")) => {case_correctly("approximate_value") => 1},
                              case_correctly("aggregated_values") => {"name" => {case_correctly("approximate_distinct_value_count") => 1}},
                              case_correctly("sub_aggregations") => {
                                case_correctly("seasons_nested") => {
                                  case_correctly("nodes") => [
                                    {
                                      case_correctly("grouped_by") => {case_correctly("year") => 2022},
                                      case_correctly(case_correctly("count_detail")) => {case_correctly("approximate_value") => 1},
                                      case_correctly("aggregated_values") => {case_correctly("games_played") => {case_correctly("exact_max") => 10}}
                                    }
                                  ]
                                }
                              }
                            },
                            {
                              case_correctly("grouped_by") => {case_correctly("name") => "Ted"},
                              case_correctly(case_correctly("count_detail")) => {case_correctly("approximate_value") => 1},
                              case_correctly("aggregated_values") => {"name" => {case_correctly("approximate_distinct_value_count") => 1}},
                              case_correctly("sub_aggregations") => {
                                case_correctly("seasons_nested") => {
                                  case_correctly("nodes") => [
                                    {
                                      case_correctly("grouped_by") => {case_correctly("year") => 2018},
                                      case_correctly(case_correctly("count_detail")) => {case_correctly("approximate_value") => 2},
                                      case_correctly("aggregated_values") => {case_correctly("games_played") => {case_correctly("exact_max") => 30}}
                                    }
                                  ]
                                }
                              }
                            }
                          ]
                        }
                      }
                    },
                    {
                      case_correctly("grouped_by") => {case_correctly("year") => 2019},
                      case_correctly(case_correctly("count_detail")) => {case_correctly("approximate_value") => 1},
                      case_correctly("aggregated_values") => {
                        "record" => {"wins" => {
                          case_correctly("approximate_avg") => 40.0,
                          case_correctly("exact_max") => 40
                        }}
                      },
                      case_correctly("sub_aggregations") => {case_correctly("players_nested") => {case_correctly("nodes") => []}}
                    },
                    {
                      case_correctly("grouped_by") => {case_correctly("year") => 2021},
                      case_correctly(case_correctly("count_detail")) => {case_correctly("approximate_value") => 1},
                      case_correctly("aggregated_values") => {
                        "record" => {"wins" => {
                          case_correctly("approximate_avg") => nil,
                          case_correctly("exact_max") => nil
                        }}
                      },
                      case_correctly("sub_aggregations") => {case_correctly("players_nested") => {case_correctly("nodes") => []}}
                    },
                    {
                      case_correctly("grouped_by") => {case_correctly("year") => 2022},
                      case_correctly(case_correctly("count_detail")) => {case_correctly("approximate_value") => 1},
                      case_correctly("aggregated_values") => {
                        "record" => {"wins" => {
                          case_correctly("approximate_avg") => 40.0,
                          case_correctly("exact_max") => 40
                        }}
                      },
                      case_correctly("sub_aggregations") => {case_correctly("players_nested") => {case_correctly("nodes") => []}}
                    },
                    {
                      case_correctly("grouped_by") => {case_correctly("year") => 2023},
                      case_correctly(case_correctly("count_detail")) => {case_correctly("approximate_value") => 1},
                      case_correctly("aggregated_values") => {
                        "record" => {"wins" => {
                          case_correctly("approximate_avg") => 50.0,
                          case_correctly("exact_max") => 50
                        }}
                      },
                      case_correctly("sub_aggregations") => {case_correctly("players_nested") => {case_correctly("nodes") => []}}
                    }
                  ]
                }
              }
            }
          ]
        })
      end

      def aggregate_count_under_extra_object_layer
        response = call_graphql_query(<<~EOS)
          query {
            team_aggregations {
              #{page_info_snippet}
              nodes {
                sub_aggregations {
                  nested_fields {
                    current_players {
                      #{page_info_snippet}
                      nodes {
                        count_detail {
                          approximate_value
                          exact_value
                          upper_bound
                        }
                      }
                    }

                    seasons {
                      #{page_info_snippet}
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
            }
          }
        EOS

        team_node = get_single_aggregations_node_from(response, "team_aggregations", parent_field_name: "data")
        player_node = get_single_aggregations_node_from(team_node, "nested_fields", "current_players")
        season_node = get_single_aggregations_node_from(team_node, "nested_fields", "seasons")

        [
          player_node.fetch(case_correctly("count_detail")),
          season_node.fetch(case_correctly("count_detail"))
        ]
      end

      def verify_sub_aggregations_with_aliases
        response = call_graphql_query(<<~EOS)
          query {
            teamaggs: team_aggregations {
              ns: nodes {
                subaggs: sub_aggregations {
                  before2021: seasons_nested(filter: {year: {lt: 2021}}) {
                    ns: nodes {
                      c: count_detail { val: approximate_value }
                      subaggs: sub_aggregations {
                        players: players_nested {
                          ns: nodes {
                            c: count_detail { val: approximate_value }
                            a: aggregated_values {
                              n1: name { val: approximate_distinct_value_count }
                              n2: name { val: approximate_distinct_value_count }
                            }
                          }
                        }
                      }
                    }
                  }

                  after2021: seasons_nested(filter: {year: {gt: 2021}}) {
                    ns: nodes {
                      c: count_detail { val: approximate_value }
                      subaggs: sub_aggregations {
                        players: players_nested {
                          ns: nodes {
                            c: count_detail { val: approximate_value }
                            a: aggregated_values {
                              n1: name { val: approximate_distinct_value_count }
                              n2: name { val: approximate_distinct_value_count }
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
        EOS

        expect(response.to_h).to eq({
          "data" => {
            "teamaggs" => {
              "ns" => [
                {
                  "subaggs" => {
                    "before2021" => {
                      "ns" => [
                        {
                          "c" => {"val" => 3},
                          "subaggs" => {
                            "players" => {
                              "ns" => [
                                {
                                  "c" => {"val" => 2},
                                  "a" => {"n1" => {"val" => 2}, "n2" => {"val" => 2}}
                                }
                              ]
                            }
                          }
                        }
                      ]
                    },
                    "after2021" => {
                      "ns" => [
                        {
                          "c" => {"val" => 2},
                          "subaggs" => {
                            "players" => {
                              "ns" => [
                                {
                                  "c" => {"val" => 0},
                                  "a" => {"n1" => {"val" => 0}, "n2" => {"val" => 0}}
                                }
                              ]
                            }
                          }
                        }
                      ]
                    }
                  }
                }
              ]
            }
          }
        })
      end

      def test_optimizable_aggregations_with_sub_aggregations
        response = call_graphql_query(<<~EOS)
          query {
            t1: team_aggregations {
              nodes { grouped_by { current_name } }
            }

            t2: team_aggregations {
              nodes {
                sub_aggregations {
                  current_players_nested {
                    nodes { count_detail { approximate_value } }
                  }
                }
              }
            }
          }
        EOS

        expect(response["data"]).to eq({
          "t1" => {"nodes" => [
            {case_correctly("grouped_by") => {case_correctly("current_name") => "Dodgers"}},
            {case_correctly("grouped_by") => {case_correctly("current_name") => "Magenta Sox"}},
            {case_correctly("grouped_by") => {case_correctly("current_name") => "Red Sox"}},
            {case_correctly("grouped_by") => {case_correctly("current_name") => "Yankees"}}
          ]},
          "t2" => {"nodes" => [{
            case_correctly("sub_aggregations") => {
              case_correctly("current_players_nested") => {
                "nodes" => [
                  {case_correctly("count_detail") => {case_correctly("approximate_value") => 5}}
                ]
              }
            }
          }]}
        })
      end

      def count_seasons_and_season_player_seasons(seasons: {}, season_player_seasons: {}, team_aggregations: {})
        response = call_graphql_query(<<~EOS)
          query {
            team_aggregations#{graphql_args(team_aggregations)} {
              #{page_info_snippet}
              nodes {
                sub_aggregations {
                  seasons_nested#{graphql_args(seasons)} {
                    #{page_info_snippet}
                    nodes {
                      count_detail {
                        approximate_value
                        exact_value
                        upper_bound
                      }

                      sub_aggregations {
                        players_nested {
                          #{page_info_snippet}
                          nodes {
                            sub_aggregations {
                              seasons_nested#{graphql_args(season_player_seasons)} {
                                #{page_info_snippet}
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
                      }
                    }
                  }
                }
              }
            }
          }
        EOS

        team_node = get_single_aggregations_node_from(response, "team_aggregations", parent_field_name: "data")
        seasons_node = get_single_aggregations_node_from(team_node, "seasons_nested")
        season_players_node = get_single_aggregations_node_from(seasons_node, "players_nested") if seasons_node
        season_player_seasons_node = get_single_aggregations_node_from(season_players_node, "seasons_nested") if season_players_node

        [
          seasons_node&.fetch(case_correctly("count_detail")),
          season_player_seasons_node&.fetch(case_correctly("count_detail"))
        ]
      end

      def aggregate_season_counts_grouped_by(*grouping_expressions, team_aggregations_args: {}, allow_errors: false, teams_has_next_page: false, seasons_has_next_page: false, **args)
        response = call_graphql_query(<<~EOS, allow_errors: allow_errors)
          query {
            team_aggregations#{graphql_args(team_aggregations_args)} {
              #{page_info_snippet}
              nodes {
                sub_aggregations {
                  seasons_nested#{graphql_args(args)} {
                    #{page_info_snippet}
                    nodes {
                      grouped_by {
                        #{grouping_expressions.join("\n")}
                      }

                      count_detail { ...count_aggregations }
                    }
                  }
                }
              }
            }
          }

          fragment count_aggregations on AggregationCountDetail {
            approximate_value
            exact_value
            upper_bound
          }
        EOS

        return response if allow_errors

        team_node = get_single_aggregations_node_from(response, "team_aggregations", parent_field_name: "data", has_next_page: teams_has_next_page)
        get_aggregations_nodes_from(team_node, "seasons_nested", has_next_page: seasons_has_next_page)
      end

      def aggregate_teams_grouped_by_league(allow_errors: false)
        response = call_graphql_query(<<~EOS, allow_errors: allow_errors)
          query {
            team_aggregations {
              nodes {
                grouped_by { league }
                aggregated_values { forbes_valuations { approximate_sum } }
                count
              }
            }
          }
        EOS

        return response if allow_errors

        response.dig("data", case_correctly("team_aggregations"), "nodes")
      end

      def get_aggregations_nodes_from(response_data, *field_names, parent_field_name: "sub_aggregations", has_next_page: false)
        field_names = field_names.map { |f| case_correctly(f) }
        connection = response_data.dig(case_correctly(parent_field_name), *field_names)

        validate_page_info_on(connection, has_next_page: has_next_page)

        connection.fetch("nodes")
      end

      def get_single_aggregations_node_from(response_data, *field_names, parent_field_name: "sub_aggregations", has_next_page: false)
        nodes = get_aggregations_nodes_from(response_data, *field_names, parent_field_name: parent_field_name, has_next_page: has_next_page)
        expect(nodes.size).to be < 2
        nodes.first
      end

      def indexed_counts_from(nodes)
        nodes.to_h do |node|
          [node.fetch(case_correctly("grouped_by")), node.dig(case_correctly("count_detail"))]
        end
      end

      def count_detail_of(count)
        {
          case_correctly("approximate_value") => count,
          case_correctly("exact_value") => count,
          case_correctly("upper_bound") => count
        }
      end

      def validate_page_info_on(connection, has_next_page:)
        nodes = connection.fetch("nodes")
        page_info = connection.fetch(case_correctly("page_info"))

        expect(page_info).to match({
          case_correctly("has_previous_page") => false,
          case_correctly("has_next_page") => has_next_page,
          case_correctly("end_cursor") => nodes.empty? ? nil : /\w+/,
          case_correctly("start_cursor") => nodes.empty? ? nil : /\w+/
        })
      end
    end
  end
end
