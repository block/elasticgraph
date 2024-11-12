# Copyright 2024 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require_relative "datastore_query_integration_support"

module ElasticGraph
  class GraphQL
    RSpec.describe DatastoreQuery, "filtering" do
      include_context "DatastoreQueryIntegrationSupport"

      specify "`equal_to_any_of`/`equalToAnyOf` filters to documents with a field matching any of the provided values" do
        index_into(
          graphql,
          widget1 = build(:widget),
          _widget2 = build(:widget),
          widget3 = build(:widget)
        )

        results = search_with_filter("id", "equal_to_any_of", ids_of(widget1, widget3))

        expect(results).to match_array(ids_of(widget1, widget3))

        # Verify that empty strings (and other types like numbers) that don't match anything are ignored.
        results2 = search_with_filter("id", "equal_to_any_of", ids_of(widget1, widget3) + ["", " ", "\n", 0])
        expect(results2).to eq(results)
      end

      it "routes the request to specific shards when an `equal_to_any_of`/`equalToAnyOf` filter is used on a custom shard routing field", :expect_search_routing do
        index_into(
          graphql,
          widget1 = build(:widget),
          _widget2 = build(:widget),
          widget3 = build(:widget)
        )

        workspace_ids = [widget1.fetch(:workspace_id), widget3.fetch(:workspace_id)]

        results = search_with_filter("workspace_id2", "equal_to_any_of", workspace_ids)
        expect(results).to match_array(ids_of(widget1, widget3))

        expect_to_have_routed_to_shards_with("main", ["widgets_rollover__*", workspace_ids.sort.join(",")])
      end

      it "avoids querying the datastore when a filter on the shard routing field excludes all values" do
        pre_cache_index_state(graphql) # so that any datastore calls needed for the index state are made before we expect no calls.

        expect {
          results = search_with_filter("workspace_id2", "equal_to_any_of", [])
          expect(results).to eq([])
        }.to make_no_datastore_calls("main")
      end

      it "still gets a well-formatted response, even when filtering to no routing values", :expect_search_routing do
        results = search_with_filter("workspace_id2", "equal_to_any_of", [])
        expect(results).to be_empty
      end

      specify "comparison range operators filter to documents with a field satisfying the comparison" do
        index_into(
          graphql,
          widget1 = build(:widget, amount_cents: 100),
          widget2 = build(:widget, amount_cents: 150),
          widget3 = build(:widget, amount_cents: 200)
        )

        expect(search_with_filter("amount_cents", "gt", 100)).to match_array(ids_of(widget2, widget3))
        expect(search_with_filter("amount_cents", "gte", 150)).to match_array(ids_of(widget2, widget3))
        expect(search_with_filter("amount_cents", "lt", 200)).to match_array(ids_of(widget1, widget2))
        expect(search_with_filter("amount_cents", "lte", 150)).to match_array(ids_of(widget1, widget2))
        expect(search_with_freeform_filter({"amount_cents" => {"gt" => 125, "lte" => 175}})).to match_array(ids_of(widget2))
      end

      specify "`near` works on a `GeoLocation` field to filter to nearby locations" do
        # The lat/long values here were pulled from Google maps.
        index_into(
          graphql,
          build(:address, id: "space_needle", geo_location: {latitude: 47.62089914996321, longitude: -122.34924708967479}),
          build(:address, id: "crystal_mtn", geo_location: {latitude: 46.93703464703253, longitude: -121.47398616597955}),
          build(:address, id: "pike_place_mkt", geo_location: {latitude: 47.60909792583577, longitude: -122.33981115022492})
        )

        downtown_seattle_location = {"latitude" => 47.6078024243176, "longitude" => -122.3345525727595}

        about_3_miles_for_each_supported_unit = {
          "MILE" => 3,
          "FOOT" => 3 * 5_280,
          "INCH" => 12 * 3 * 5_280,
          "YARD" => 5_280,
          "KILOMETER" => 4.828,
          "METER" => 4_828,
          "CENTIMETER" => 482_800,
          "MILLIMETER" => 4_828_000,
          "NAUTICAL_MILE" => 2.6
        }
        expect(about_3_miles_for_each_supported_unit.keys).to match_array(graphql.runtime_metadata.enum_types_by_name.fetch("DistanceUnitInput").values_by_name.keys)

        about_3_miles_for_each_supported_unit.each do |unit, distance|
          near_filter = downtown_seattle_location.merge(
            "max_distance" => distance,
            "unit" => enum_value("DistanceUnitInput", unit)
          )

          aggregate_failures "filtering with #{unit} unit" do
            near_downtown_seattle = search_with_freeform_filter(
              {"geo_location" => {"near" => near_filter}},
              index_def_name: "addresses"
            )
            expect(near_downtown_seattle).to contain_exactly("space_needle", "pike_place_mkt")

            not_near_downtown_seattle = search_with_freeform_filter(
              {"geo_location" => {"not" => {"near" => near_filter}}},
              index_def_name: "addresses"
            )
            expect(not_near_downtown_seattle).to contain_exactly("crystal_mtn")
          end
        end
      end

      describe "`all_of` operator" do
        it "can be used to wrap multiple `any_satisfy` expressions to require multiple sub-filters to be satisfied by a list element" do
          index_into(
            graphql,
            team1 = build(:team, forbes_valuations: [1_000_000, 100_000_000]),
            team2 = build(:team, forbes_valuations: []),
            team3 = build(:team, forbes_valuations: [3_000_000])
          )

          results = search_with_filter("forbes_valuations", "any_satisfy", {"gt" => 2_000_000, "lt" => 5_000_000})
          # With a single (gt > 2M, lt < 5M) filter, only team3 (3M) qualifies...
          expect(results).to match_array(ids_of(team3))

          results = search_with_filter("forbes_valuations", "all_of", [
            {"any_satisfy" => {"gt" => 2_000_000}},
            {"any_satisfy" => {"lt" => 5_000_000}}
          ])
          # ...but when you split them into separate `all_of` clauses, team1 (1M, 100M) also qualifies.
          expect(results).to match_array(ids_of(team1, team3))

          results = search_with_filter("forbes_valuations", "all_of", nil)
          # all teamss qualify for `all_of: nil`
          expect(results).to match_array(ids_of(team1, team2, team3))

          results = search_with_filter("forbes_valuations", "all_of", [])
          # all teamss qualify for `all_of: []`
          expect(results).to match_array(ids_of(team1, team2, team3))
        end

        def search_datastore(**options, &before_msearch)
          super(index_def_name: "teams", **options, &before_msearch)
        end
      end

      describe "`any_satisfy` filtering" do
        context "when used on a list-of-scalars field" do
          it "matches documents that have a list element matching the provided subfilter" do
            index_into(
              graphql,
              team1 = build(:team, past_names: ["foo", "bar"]),
              _team2 = build(:team, past_names: ["bar"]),
              team3 = build(:team, past_names: ["bar", "bazz"])
            )

            expect(search_with_filter(
              "past_names", "any_satisfy", {"equal_to_any_of" => ["foo", "bazz"]}
            )).to match_array(ids_of(team1, team3))
          end

          it "supports `not: {any_satisfy: ...}`, returning documents where their list field has no elements matching the provided subfilter" do
            index_into(
              graphql,
              _team1 = build(:team, id: "t1", past_names: ["a", "b"]),
              team2 = build(:team, id: "t2", past_names: ["b", "c"]),
              team3 = build(:team, id: "t3", past_names: []),
              _team4 = build(:team, id: "t4", past_names: ["a"])
            )

            expect(search_with_filter(
              "past_names", "not", {"any_satisfy" => {"equal_to_any_of" => ["a"]}}
            )).to match_array(ids_of(team2, team3))
          end

          it "supports `any_satisfy: {time_of_day: ...}` filtering on a list-of-timestamps field" do
            index_into(
              graphql,
              team1 = build(:team, id: "t1", won_championships_at: [], seasons: [
                build(:team_season, started_at: "2015-04-01T12:30:00Z", won_games_at: ["2015-04-08T15:30:00Z", "2015-04-09T16:30:00Z"])
              ]),
              team2 = build(:team, id: "t2", won_championships_at: ["2013-11-27T02:30:00Z", "2013-11-27T22:30:00Z"], seasons: [
                build(:team_season, started_at: "2015-04-01T12:30:00Z", won_games_at: ["2015-04-08T02:30:00Z"]),
                build(:team_season, started_at: "2015-04-01T02:30:00Z", won_games_at: ["2015-04-08T03:30:00Z", "2015-04-09T04:30:00Z"])
              ]),
              team3 = build(:team, id: "t3", won_championships_at: ["2003-10-27T19:30:00Z"], seasons: []),
              team4 = build(:team, id: "t4", won_championships_at: ["2005-10-27T12:30:00Z"], seasons: [
                build(:team_season, started_at: "2015-04-01T19:30:00Z", won_games_at: [])
              ])
            )

            # On a list-of-scalars field on the root doc
            expect(search_with_filter(
              "won_championships_at", "any_satisfy", {"time_of_day" => {"gt" => "15:00:00", "time_zone" => "UTC"}}
            )).to match_array(ids_of(team2, team3))

            # On a list-of-scalars field on the root doc with a non-UTC timezone
            expect(search_with_filter(
              "won_championships_at", "any_satisfy", {"time_of_day" => {"lte" => "08:00:00", "time_zone" => "America/Los_Angeles"}}
            )).to match_array(ids_of(team4))

            # On a singleton scalar field under a nested field
            expect(search_with_filter(
              "seasons_nested", "any_satisfy", {"started_at" => {"time_of_day" => {"gt" => "18:00:00", "time_zone" => "UTC"}}}
            )).to match_array(ids_of(team4))

            # On a list-of-scalars field under a nested field
            expect(search_with_filter(
              "seasons_nested", "any_satisfy", {"won_games_at" => {"any_satisfy" => {"time_of_day" => {"gt" => "14:00:00", "time_zone" => "UTC"}}}}
            )).to match_array(ids_of(team1))

            # On a singleton scalar field under an object field
            expect(search_with_filter(
              "seasons_object", "started_at", {"time_of_day" => {"gt" => "18:00:00", "time_zone" => "UTC"}}
            )).to match_array(ids_of(team4))

            # On a list-of-scalars field under an object field
            expect(search_with_filter(
              "seasons_object", "won_games_at", {"any_satisfy" => {"time_of_day" => {"gt" => "14:00:00", "time_zone" => "UTC"}}}
            )).to match_array(ids_of(team1))
          end

          it "supports `any_satisfy: {...}` with range operators on a list-of-numbers field" do
            index_into(
              graphql,
              _team1 = build(:team, id: "t1", forbes_valuations: []),
              team2 = build(:team, id: "t2", forbes_valuations: [10_000_000]),
              team3 = build(:team, id: "t3", forbes_valuations: [0, 500_000_000]),
              team4 = build(:team, id: "t4", forbes_valuations: [5000, 250_000_000])
            )

            expect(search_with_filter(
              "forbes_valuations", "any_satisfy", {"gt" => 100_000_000}
            )).to match_array(ids_of(team3, team4))

            expect(search_with_filter(
              "forbes_valuations", "any_satisfy", {"lt" => 100_000_000}
            )).to match_array(ids_of(team2, team3, team4))

            expect(search_with_filter(
              "forbes_valuations", "any_satisfy", {"gt" => 10_000, "lt" => 500_000_000}
            )).to match_array(ids_of(team2, team4))

            expect(search_with_filter(
              # We don't expect users to use all 4 range operators, but if they do it should work!
              "forbes_valuations", "any_satisfy", {"gt" => 10_000, "gte" => 20_000, "lt" => 500_000_000, "lte" => 100_000_000}
            )).to match_array(ids_of(team2))
          end
        end

        context "when used on a list-of-nested-objects field" do
          it "can correctly consider each nested object independently, correctly matching on multiple filters" do
            index_into(
              graphql,
              _team1 = build(:team, current_players: [build(:player, name: "Babe Truth", nicknames: ["The Truth"])]),
              team2 = build(:team, current_players: [
                build(:player, name: "Babe Truth", nicknames: ["The Babe", "Bambino"]),
                build(:player, name: "Johnny Rocket", nicknames: ["The Rocket"])
              ]),
              _team3 = build(:team, current_players: [
                build(:player, name: "Ichiro", nicknames: ["Bambino"]),
                build(:player, name: "Babe Truth", nicknames: ["The Wizard"])
              ]),
              _team4 = build(:team, current_players: [])
            )

            results = search_with_filter("current_players_nested", "any_satisfy", {
              "name" => {"equal_to_any_of" => ["Babe Truth"]},
              "nicknames" => {"any_satisfy" => {"equal_to_any_of" => ["Bambino"]}}
            })

            expect(results).to match_array(ids_of(team2))
          end

          it "correctly treats nil filters under `any_satisfy` treating as `true`" do
            results = search_with_filter("current_players_nested", "any_satisfy", {
              "name" => {"equal_to_any_of" => nil},
              "nicknames" => {"any_satisfy" => {"equal_to_any_of" => nil}}
            })

            # Results are empty since nothing has been indexed here. The original regression this test guards against
            # is an exception produced by Elasticsearch/OpenSearch, so we primarily care about it not raising an
            # exception here.
            expect(results).to be_empty
          end
        end

        def search_datastore(**options, &before_msearch)
          super(index_def_name: "teams", **options, &before_msearch)
        end
      end

      # Note: a `count` filter gets translated into `__counts` (to distinguish it from a schema field named `count`),
      # and that translation happens as the query is being built, so we use `__counts` in our example filters here.
      describe "`count` filtering on a list" do
        it "matches documents with a root list count matching the filter" do
          index_into(
            graphql,
            _team1 = build(:team, past_names: ["a", "b", "c", "d"]),
            team2 = build(:team, past_names: ["a", "b", "c"]),
            _team3 = build(:team, past_names: ["a", "b"])
          )

          results = search_with_freeform_filter({"past_names" => {LIST_COUNTS_FIELD => {"gt" => 2, "lt" => 4}}})
          expect(results).to match_array(ids_of(team2))
        end

        it "matches documents with a list count under an object field" do
          index_into(
            graphql,
            _team1 = build(:team, details: {uniform_colors: ["a", "b", "c", "d"]}),
            team2 = build(:team, details: {uniform_colors: ["a", "b", "c"]}),
            _team1 = build(:team, details: {uniform_colors: ["a", "b"]})
          )

          results = search_with_freeform_filter({"details" => {"uniform_colors" => {LIST_COUNTS_FIELD => {"gt" => 2, "lt" => 4}}}})
          expect(results).to match_array(ids_of(team2))
        end

        it "correctly matches a list field under a list-of-nested objects" do
          index_into(
            graphql,
            team1 = build(:team, seasons: [
              build(:team_season, notes: ["a", "b", "c"])
            ]),
            _team2 = build(:team, seasons: [
              build(:team_season, notes: ["a", "b"]),
              build(:team_season, notes: ["a", "b", "c", "d"])
            ]),
            _team3 = build(:team, seasons: [])
          )

          results = search_with_freeform_filter({"seasons_nested" => {"any_satisfy" => {"notes" => {LIST_COUNTS_FIELD => {"gt" => 2, "lt" => 4}}}}})
          expect(results).to match_array(ids_of(team1))
        end

        it "treats a filter on a `count` schema field like a filter on any other schema field" do
          index_into(
            graphql,
            team1 = build(:team, details: {count: 50}),
            _team2 = build(:team, details: {count: 40})
          )

          results = search_with_freeform_filter({"details" => {"count" => {"gt" => 45}}})
          expect(results).to match_array(ids_of(team1))
        end

        context "when filtering in a way that matches a count of zero" do
          it "matches documents that have no record of the count since that indicates they were indexed before the list field was defined, and they therefore have no values for it" do
            index_into(
              graphql,
              team1 = build(:team)
            )

            results = search_with_freeform_filter({"some_new_field_defined_after_indexing" => {LIST_COUNTS_FIELD => {"lt" => 1}}})
            expect(results).to match_array(ids_of(team1))
            results = search_with_freeform_filter({"some_new_field_defined_after_indexing" => {LIST_COUNTS_FIELD => {"gt" => -1}}})
            expect(results).to match_array(ids_of(team1))
            results = search_with_freeform_filter({"some_new_field_defined_after_indexing" => {LIST_COUNTS_FIELD => {"lte" => 0}}})
            expect(results).to match_array(ids_of(team1))
            results = search_with_freeform_filter({"some_new_field_defined_after_indexing" => {LIST_COUNTS_FIELD => {"gte" => 0}}})
            expect(results).to match_array(ids_of(team1))
            results = search_with_freeform_filter({"some_new_field_defined_after_indexing" => {LIST_COUNTS_FIELD => {"equal_to_any_of" => [3, 0, 10]}}})
            expect(results).to match_array(ids_of(team1))

            results = search_with_freeform_filter({"some_new_field_defined_after_indexing" => {LIST_COUNTS_FIELD => {"lt" => 0}}})
            expect(results).to be_empty
            results = search_with_freeform_filter({"some_new_field_defined_after_indexing" => {LIST_COUNTS_FIELD => {"gt" => 0}}})
            expect(results).to be_empty
            results = search_with_freeform_filter({"some_new_field_defined_after_indexing" => {LIST_COUNTS_FIELD => {"lte" => -1}}})
            expect(results).to be_empty
            results = search_with_freeform_filter({"some_new_field_defined_after_indexing" => {LIST_COUNTS_FIELD => {"gte" => 1}}})
            expect(results).to be_empty
            results = search_with_freeform_filter({"some_new_field_defined_after_indexing" => {LIST_COUNTS_FIELD => {"equal_to_any_of" => [3, 10]}}})
            expect(results).to be_empty
          end
        end

        def search_datastore(**options, &before_msearch)
          super(index_def_name: "teams", **options, &before_msearch)
        end
      end

      describe "`time_of_day` filtering", :builds_admin do
        # When working on the logic of the `filter/by_time_of_day.painless` script, it makes the feedback cycle slow
        # to have to run `bundle exec rake schema_artifacts:dump` after each change in the script before it can be used
        # by the test here. To have a faster feedback cycle, I added this before hook that uses a custom (empty) schema
        # definition, runs our script configurators, and updates the `static_script_ids_by_scoped_name` to the new script
        # id. With this before hook in place, changes in the script immediately go into effect when we run the tests here.
        #
        # However, if you're not actively editing the script it's not needed to run this extra bit of setup (and is
        # undesirable since it slows things down a bit).
        #
        # So, here we detect if the script file has changed since the last time RSpec ran.
        rspec_results_file = ::File.join(CommonSpecHelpers::REPO_ROOT, "tmp", "rspec", "stats.txt")
        filter_by_time_of_day_file = ::File.join([
          CommonSpecHelpers::REPO_ROOT,
          "elasticgraph-schema_definition",
          "lib",
          "elastic_graph",
          "schema_definition",
          "scripting",
          "scripts",
          "filter",
          "by_time_of_day.painless"
        ])

        if ::File.exist?(rspec_results_file) && ::File.mtime(rspec_results_file) < ::File.mtime(filter_by_time_of_day_file)
          # :nocov: -- often skipped
          before do
            admin = build_admin(schema_definition: ->(schema) {})

            admin
              .cluster_configurator.send(:script_configurators_for, $stdout)
              .each(&:configure!)

            graphql.runtime_metadata.static_script_ids_by_scoped_name.replace(
              admin.schema_artifacts.runtime_metadata.static_script_ids_by_scoped_name
            )
          end
          # :nocov:
        end

        it "supports gt/gte/lt/lte/equal_to_any_of operators, honoring the given time zone" do
          index_into(
            graphql,
            # In 2022, DST started on 2022-03-13, so on this date the Pacific Time offset was -8 hours.
            widget_02am = build(:widget, id: "02am", created_at: "2022-03-12T10:23:10Z"), # Local time in Pacific: 02:23:10
            # ...on on this date the Pacific Time offset was -7 hours.
            widget_03am = build(:widget, id: "03am", created_at: "2022-03-13T10:23:10Z"), # Local time in Pacific: 03:23:10
            # ...and on this date the Pacific Time offset was -7 hours.
            widget_08pm = build(:widget, id: "08pm", created_at: "2022-04-12T03:05:00Z"), # Local time in Pacific: 20:05:00
            # In 2022, DST ended on 2022-11-06, so on this date the Pacific Time offset was -7 hours.
            widget_11am = build(:widget, id: "11am", created_at: "2022-11-05T18:45:23.987Z"), # Local time in Pacific: 11:45:23.987
            # ...and on this date the Pacific Time offset was -8 hours.
            widget_10am = build(:widget, id: "10am", created_at: "2022-11-07T18:45:23.987Z") # Local time in Pacific: 10:45:23.987
          )

          # First, test gte. Use a LocalTime value exactly equal to one of the timestamps...
          results = search_with_freeform_filter({
            "created_at" => {"time_of_day" => {"gte" => "10:45:23.987", "time_zone" => "America/Los_Angeles"}}
          })
          expect(results).to match_array(ids_of(widget_10am, widget_11am, widget_08pm))
          # ...and then go 1 ms later to show that result is excluded.
          results = search_with_freeform_filter({
            "created_at" => {"time_of_day" => {"gte" => "10:45:23.988", "time_zone" => "America/Los_Angeles"}}
          })
          expect(results).to match_array(ids_of(widget_11am, widget_08pm))

          # Next, test gt. Use a LocalTime 1 ms less than one of the timestamps...
          results = search_with_freeform_filter({
            "created_at" => {"time_of_day" => {"gt" => "10:45:23.986", "time_zone" => "America/Los_Angeles"}}
          })
          expect(results).to match_array(ids_of(widget_10am, widget_11am, widget_08pm))
          # ...and then go 1 ms later to show that result is excluded.
          results = search_with_freeform_filter({
            "created_at" => {"time_of_day" => {"gt" => "10:45:23.987", "time_zone" => "America/Los_Angeles"}}
          })
          expect(results).to match_array(ids_of(widget_11am, widget_08pm))

          # Next, test lte. Use a LocalTime value exactly equal to one of the timestamps...
          results = search_with_freeform_filter({
            "created_at" => {"time_of_day" => {"lte" => "11:45:23.987", "time_zone" => "America/Los_Angeles"}}
          })
          expect(results).to match_array(ids_of(widget_11am, widget_10am, widget_02am, widget_03am))
          # ...and then go 1 ms earlier to show that result is excluded.
          results = search_with_freeform_filter({
            "created_at" => {"time_of_day" => {"lte" => "11:45:23.986", "time_zone" => "America/Los_Angeles"}}
          })
          expect(results).to match_array(ids_of(widget_10am, widget_02am, widget_03am))

          # Next, test lt. Use a LocalTime 1 ms more than one of the timestamps...
          results = search_with_freeform_filter({
            "created_at" => {"time_of_day" => {"lt" => "11:45:23.988", "time_zone" => "America/Los_Angeles"}}
          })
          expect(results).to match_array(ids_of(widget_11am, widget_10am, widget_02am, widget_03am))
          # ...and then go 1 ms earlier to show that result is excluded.
          results = search_with_freeform_filter({
            "created_at" => {"time_of_day" => {"lt" => "11:45:23.987", "time_zone" => "America/Los_Angeles"}}
          })
          expect(results).to match_array(ids_of(widget_10am, widget_02am, widget_03am))

          # Next, test `equal_to_any_of` with 2 values that match records and one that doesn't.
          results = search_with_freeform_filter({
            "created_at" => {"time_of_day" => {
              "equal_to_any_of" => ["20:05:00", "03:23:10", "23:12:12"],
              "time_zone" => "America/Los_Angeles"
            }}
          })
          expect(results).to match_array(ids_of(widget_08pm, widget_03am))

          # Finally, combine multiple operators in one filter to show that works.
          results = search_with_freeform_filter({
            "created_at" => {"time_of_day" => {
              "gte" => "02:30:00",
              "lt" => "12:00:00",
              "time_zone" => "America/Los_Angeles"
            }}
          })
          expect(results).to match_array(ids_of(widget_03am, widget_10am, widget_11am))
        end

        it "works on nested DateTime scalar fields" do
          index_into(
            graphql,
            # In 2022, DST started on 2022-03-13, so on this date the Pacific Time offset was -8 hours.
            address_02am = build(:address, id: "02am", timestamps: {created_at: "2022-03-12T10:23:10Z"}), # Local time in Pacific: 02:23:10
            # ...and on this date the Pacific Time offset was -7 hours.
            address_08pm = build(:address, id: "08pm", timestamps: {created_at: "2022-04-12T03:05:00Z"}) # Local time in Pacific: 20:05:00
          )

          results = search_with_freeform_filter({
            "timestamps" => {"created_at" => {"time_of_day" => {"gte" => "12:00:00", "time_zone" => "America/Los_Angeles"}}}
          }, index_def_name: "addresses")
          expect(results).to match_array(ids_of(address_08pm))

          results = search_with_freeform_filter({
            "timestamps" => {"created_at" => {"time_of_day" => {"lte" => "12:00:00", "time_zone" => "America/Los_Angeles"}}}
          }, index_def_name: "addresses")
          expect(results).to match_array(ids_of(address_02am))
        end

        it "does not match documents that have `null` for their timestamp field value" do
          index_into(
            graphql,
            build(:address, timestamps: {created_at: nil})
          )

          results = search_with_freeform_filter({
            "timestamps" => {"created_at" => {"time_of_day" => {"gte" => "00:00:00", "time_zone" => "America/Los_Angeles"}}}
          }, index_def_name: "addresses")
          expect(results).to be_empty

          results = search_with_freeform_filter({
            "timestamps" => {"created_at" => {"time_of_day" => {"lte" => "23:59:59.999", "time_zone" => "America/Los_Angeles"}}}
          }, index_def_name: "addresses")
          expect(results).to be_empty
        end

        it "works correctly with compound filter operators like `not` and `any_of`" do
          index_into(
            graphql,
            # In 2022, DST started on 2022-03-13, so on this date the Pacific Time offset was -8 hours.
            widget_02am = build(:widget, id: "02am", created_at: "2022-03-12T10:23:10Z"), # Local time in Pacific: 02:23:10
            # ...and on this date the Pacific Time offset was -7 hours.
            widget_08pm = build(:widget, id: "08pm", created_at: "2022-04-12T03:05:00Z"), # Local time in Pacific: 20:05:00
            # In 2022, DST ended on 2022-11-06, so on this date the Pacific Time offset was -7 hours.
            widget_11am = build(:widget, id: "11am", created_at: "2022-11-05T18:45:23.987Z") # Local time in Pacific: 11:45:23.987
          )

          results = search_with_freeform_filter({
            "created_at" => {"time_of_day" => {"gte" => "12:00:00", "time_zone" => "America/Los_Angeles"}}
          })
          expect(results).to match_array(ids_of(widget_08pm))

          # Try `not` outside of `time_of_day`: it should be the inverse of the above
          results = search_with_freeform_filter({
            "created_at" => {"not" => {"time_of_day" => {"gte" => "12:00:00", "time_zone" => "America/Los_Angeles"}}}
          })
          expect(results).to match_array(ids_of(widget_02am, widget_11am))

          # Try `any_of` outside of `time_of_day`: it should OR together conditions correctly.
          results = search_with_freeform_filter({
            "created_at" => {"any_of" => [
              {"time_of_day" => {"gte" => "12:00:00", "time_zone" => "America/Los_Angeles"}},
              {"time_of_day" => {"lte" => "10:00:00", "time_zone" => "America/Los_Angeles"}}
            ]}
          })
          expect(results).to match_array(ids_of(widget_08pm, widget_02am))

          # Note: `any_of` and `not` are intentionally not supported inside a `time_of_day` filter at this time.
        end

        it "matches all documents when the filter includes no operators" do
          index_into(
            graphql,
            widget = build(:widget, id: "02am")
          )

          results = search_with_freeform_filter({
            "created_at" => {"time_of_day" => {"time_zone" => "America/Los_Angeles"}}
          })
          expect(results).to match_array(ids_of(widget))

          results = search_with_freeform_filter({
            "created_at" => {"time_of_day" => {}}
          })
          expect(results).to match_array(ids_of(widget))
        end
      end

      context "when range operators are used with timestamp strings" do
        it "applies the filtering and also excludes rollover indices from being searched which cannot contain any matching documents", :expect_index_exclusions do
          index_into(
            graphql,
            widget1 = build(:widget, created_at: (t1 = "2019-05-10T12:00:00Z")),
            widget2 = build(:widget, created_at: (t2 = "2019-05-15T12:00:00Z")),
            widget3 = build(:widget, created_at: (t3 = "2019-05-20T12:00:00Z"))
          )

          expect(search_with_filter("created_at", "gt", t1)).to match_array(ids_of(widget2, widget3))
          expect_to_have_excluded_indices("main", ["widgets_rollover__before_2019"])

          expect(search_with_filter("created_at", "gte", t2)).to match_array(ids_of(widget2, widget3))
          expect_to_have_excluded_indices("main", ["widgets_rollover__before_2019"])

          expect(search_with_filter("created_at", "lt", t3)).to match_array(ids_of(widget1, widget2))
          expect_to_have_excluded_indices("main", ["widgets_rollover__2020", "widgets_rollover__2021", "widgets_rollover__after_2021"])

          expect(search_with_filter("created_at", "lte", t2)).to match_array(ids_of(widget1, widget2))
          expect_to_have_excluded_indices("main", ["widgets_rollover__2020", "widgets_rollover__2021", "widgets_rollover__after_2021"])

          expect {
            expect(search_with_freeform_filter({"created_at" => {"gte" => t2, "lt" => t2}})).to eq []
          }.to make_no_datastore_calls("main")
        end

        context "when the configuration does not agree with the indices that exist in the datastore", :expect_index_exclusions do
          let(:graphql) do
            index_defs = ::Hash.new do |hash, index_def_name|
              hash[index_def_name] = config_index_def_of
            end

            standard_test_custom_timestamp_ranges = CommonSpecHelpers
              .parsed_test_settings_yaml
              .dig("datastore", "index_definitions", "widgets", "custom_timestamp_ranges")
              .map { |r| r["index_name_suffix"] }

            expect(standard_test_custom_timestamp_ranges).to contain_exactly("before_2019", "after_2021")
            index_defs["widgets"] = config_index_def_of(
              # Here we omit the `after_2021` custom timestamp range that our test config normally defines
              # (and for which an index already exists in the datastore).
              custom_timestamp_ranges: [
                {
                  index_name_suffix: "before_2019",
                  lt: "2019-01-01T00:00:00Z",
                  setting_overrides: {}
                }
              ],
              # Here we define an extra index which does not exist in the datastore.
              setting_overrides_by_timestamp: {
                "2047-01-01T00:00:00Z" => {}
              }
            )

            build_graphql(index_definitions: index_defs)
          end

          it "does not attempt to exclude non-existent indices from being searched since the datastore returns an error if we do that" do
            index_into(
              build_graphql, # must build a fresh `graphql` instance because the indexer will fail due to the configured indices that haven't been created.
              widget1 = build(:widget, created_at: (t1 = "2019-05-10T12:00:00Z"))
            )

            expect(search_with_filter("created_at", "gte", t1)).to match_array(ids_of(widget1))
            expect_to_have_excluded_indices("main", ["widgets_rollover__before_2019"])
          end
        end
      end

      specify "`matches` filters using full text search" do
        index_into(
          graphql,
          widget1 = build(:widget, name_text: "a blue thing"),
          widget2 = build(:widget, name_text: "a red thing"),
          _widget3 = build(:widget, name_text: "entirely different name"),
          widget4 = build(:widget, name_text: "a thing that is blue"),
          widget5 = build(:widget, name_text: "a blue device")
        )

        results = search_with_filter("name_text", "matches", "blue thing")

        expect(results).to match_array(ids_of(widget1, widget2, widget4, widget5))
      end

      specify "`matches` filters using full text search with flexible options" do
        index_into(
          graphql,
          widget1 = build(:widget, name_text: "a blue thing"),
          widget2 = build(:widget, name_text: "a red thing"),
          _widget3 = build(:widget, name_text: "entirely different name"),
          widget4 = build(:widget, name_text: "a thing that is blue"),
          widget5 = build(:widget, name_text: "a blue device")
        )

        results = search_with_filter(
          "name_text",
          "matches_query",
          {
            "query" => "blue thang",
            # `DYNAMIC` is the GraphQL default
            "allowed_edits_per_term" => enum_value("MatchesQueryAllowedEditsPerTermInput", "DYNAMIC"),
            # `false` is the GraphQL default
            "require_all_terms" => false
          }
        )
        expect(results).to match_array(ids_of(widget1, widget2, widget4, widget5))

        results = search_with_filter(
          "name_text",
          "matches_query",
          {
            "query" => "blue thang",
            "allowed_edits_per_term" => enum_value("MatchesQueryAllowedEditsPerTermInput", "NONE"),
            # `false` is the GraphQL default
            "require_all_terms" => false
          }
        )
        # Only matches based on "blue" now since "thang" cannot be edited to "thing".
        # widget2 ("a red thing") is not included as a result.
        expect(results).to match_array(ids_of(widget1, widget4, widget5))

        results = search_with_filter(
          "name_text",
          "matches_query",
          {
            "query" => "blue thing",
            # `DYNAMIC` is the GraphQL default
            "allowed_edits_per_term" => enum_value("MatchesQueryAllowedEditsPerTermInput", "DYNAMIC"),
            "require_all_terms" => true
          }
        )
        # widget2 has "thing" but not "blue", so is excluded.
        # widget5 has "blue" but not "thing", so is excluded.
        expect(results).to match_array(ids_of(widget1, widget4))
      end

      specify "`matches_phrase` filters on an entire phrase" do
        index_into(
          graphql,
          _widget1 = build(:widget, name_text: "a blue thing"),
          _widget2 = build(:widget, name_text: "a red thing"),
          _widget3 = build(:widget, name_text: "entirely different name"),
          _widget4 = build(:widget, name_text: "a thing that is blue"),
          widget5 = build(:widget, name_text: "a blue device"),
          _widget6 = build(:widget, name_text: "a blue or green device")
        )

        results = search_with_filter("name_text", "matches_phrase", {"phrase" => "blue device"})

        expect(results).to match_array(ids_of(widget5))
      end

      specify "`matches_phrase` filters on an entire phrase also with prefix" do
        index_into(
          graphql,
          widget1 = build(:widget, name_text: "entirely new thing"),
          _widget2 = build(:widget, name_text: "entirely new device")
        )

        results = search_with_filter("name_text", "matches_phrase", {"phrase" => "entirely new t"})

        expect(results).to match_array(ids_of(widget1))
      end

      specify "`any_of` supports ORing multiple filters for flat fields" do
        index_into(
          graphql,
          widget1 = build(:widget, amount_cents: 50),
          widget2 = build(:widget, amount_cents: 100),
          _widget3 = build(:widget, amount_cents: 150),
          _widget4 = build(:widget, amount_cents: 200),
          _widget5 = build(:widget, amount_cents: 250)
        )

        results = search_with_filter("amount_cents", "any_of", [
          {"equal_to_any_of" => [50]},
          {"equal_to_any_of" => [100]}
        ])

        expect(results).to match_array(ids_of(widget1, widget2))
      end

      specify "`any_of` supports ORing multiple filters for nested fields" do
        index_into(
          graphql,
          widget1 = build(:widget, options: {size: "SMALL", color: "BLUE"}),
          _widget2 = build(:widget, options: {size: "LARGE", color: "RED"}),
          widget3 = build(:widget, options: {size: "MEDIUM", color: "RED"})
        )

        results = search_with_freeform_filter({
          "options" => {
            "any_of" => [
              {"size" => {"equal_to_any_of" => [size_of("SMALL")]}},
              {"size" => {"equal_to_any_of" => [size_of("MEDIUM")]}}
            ]
          }
        })

        expect(results).to match_array(ids_of(widget1, widget3))
      end

      specify "`any_of` supports both term and text searches" do
        index_into(
          graphql,
          _widget1 = build(:widget, name_text: "a blue thing", options: {size: "SMALL"}),
          widget2 = build(:widget, name_text: "a red thing", options: {size: "MEDIUM"}),
          _widget3 = build(:widget, name_text: "a black thing", options: {size: "MEDIUM"}),
          _widget4 = build(:widget, name_text: "another red thing", options: {size: "SMALL"}),
          _widget5 = build(:widget, name_text: "a green thing", options: {size: "SMALL"})
        )

        results = search_with_freeform_filter({
          "options" => {
            "size" => {"equal_to_any_of" => [size_of("MEDIUM")]}
          },
          "name_text" => {
            "any_of" => [
              {"matches" => "red"},
              {"matches" => "blue"}
            ]
          }
        })

        expect(results).to match_array(ids_of(widget2))
      end

      specify "`any_of` supports multiple levels of itself" do
        index_into(
          graphql,
          widget1 = build(:widget, name_text: "a blue thing", options: {size: "SMALL"}),
          widget2 = build(:widget, name_text: "a red thing", options: {size: "MEDIUM"}),
          widget3 = build(:widget, name_text: "a green thing", options: {size: "SMALL"}),
          _widget4 = build(:widget, name_text: "another red thing", options: {size: "SMALL"}),
          widget5 = build(:widget, name_text: "another green thing", options: {size: "SMALL"})
        )

        results = search_with_freeform_filter({
          "any_of" => [
            {
              "name_text" => {
                "any_of" => [
                  {"matches" => "blue"},
                  {"matches" => "green"}
                ]
              }
            },
            {
              "options" => {"size" => {"equal_to_any_of" => [size_of("MEDIUM")]}}
            }
          ]
        })

        expect(results).to match_array(ids_of(widget1, widget2, widget3, widget5))
      end

      specify "`any_of` used at nested cousin nodes works correctly" do
        index_into(
          graphql,
          # should not match; while cost matches (twice, actually), options does not match.
          _widget1 = build(:widget, options: {size: "SMALL", color: "GREEN"}, cost: {currency: "USD", amount_cents: 100}),
          # should match: cost.currency and options.size both match
          widget2 = build(:widget, options: {size: "MEDIUM", color: "GREEN"}, cost: {currency: "USD", amount_cents: 200}),
          # should not match: while options.color matches, cost does not match
          _widget3 = build(:widget, options: {size: "SMALL", color: "RED"}, cost: {currency: "GBP", amount_cents: 200}),
          # should match: cost.amount_cents and options.color both match
          widget4 = build(:widget, options: {size: "SMALL", color: "RED"}, cost: {currency: "GBP", amount_cents: 100}),
          # should not match; while options matches (twice, actually), cost does not match.
          _widget5 = build(:widget, options: {size: "MEDIUM", color: "RED"}, cost: {currency: "GBP", amount_cents: 200})
        )

        results = search_with_freeform_filter({
          "cost" => {
            "any_of" => [
              {"currency" => {"equal_to_any_of" => ["USD"]}},
              {"amount_cents" => {"equal_to_any_of" => [100]}}
            ]
          },
          "options" => {
            "any_of" => [
              {"size" => {"equal_to_any_of" => [size_of("MEDIUM")]}},
              {"color" => {"equal_to_any_of" => [color_of("RED")]}}
            ]
          }
        })

        expect(results).to match_array(ids_of(widget2, widget4))
      end

      specify "`equal_to_any_of: []` or `any_of: []` matches no documents, but `any_predicate: nil` or `field: {}` is treated as `true`, matching all documents" do
        index_into(
          graphql,
          widget1 = build(:widget),
          widget2 = build(:widget)
        )

        expect(search_with_filter("id", "equal_to_any_of", [])).to eq []
        expect(search_with_filter("id", "any_of", [])).to eq []
        expect(search_with_filter("id", "any_of", [{"any_of" => []}])).to eq []

        expect(search_with_filter("id", "equal_to_any_of", nil)).to eq ids_of(widget1, widget2)
        expect(search_with_filter("amount_cents", "lt", nil)).to eq ids_of(widget1, widget2)
        expect(search_with_filter("amount_cents", "lte", nil)).to eq ids_of(widget1, widget2)
        expect(search_with_filter("amount_cents", "gt", nil)).to eq ids_of(widget1, widget2)
        expect(search_with_filter("amount_cents", "gte", nil)).to eq ids_of(widget1, widget2)
        expect(search_with_filter("amount_cents", "any_of", nil)).to eq ids_of(widget1, widget2)
        expect(search_with_filter("name_text", "matches", nil)).to eq ids_of(widget1, widget2)
        expect(search_with_filter("name_text", "matches_query", nil)).to eq ids_of(widget1, widget2)
        expect(search_with_filter("name_text", "matches_phrase", nil)).to eq ids_of(widget1, widget2)
        expect(search_with_freeform_filter({"id" => {}})).to eq ids_of(widget1, widget2)
        expect(search_with_freeform_filter({"any_of" => [{"id" => nil}]})).to eq ids_of(widget1, widget2)
        expect(search_with_freeform_filter({"any_of" => [{"id" => nil}, {"amount_cents" => {"lt" => 0}}]})).to eq ids_of(widget1, widget2)
      end

      specify "`not: {any_of: []}` matches all documents, but `not: {any_of: [field: nil, ...]}` is treated as `false` matching no documents" do
        index_into(
          graphql,
          widget1 = build(:widget, id: "one"),
          widget2 = build(:widget, id: "two")
        )

        expect(search_with_freeform_filter({"not" => {"any_of" => []}})).to eq ids_of(widget1, widget2)
        expect(search_with_freeform_filter({"not" => {"not" => {"any_of" => []}}})).to eq []

        expect(search_with_freeform_filter({"not" => {"any_of" => [{"id" => nil}]}})).to eq []
        expect(search_with_freeform_filter({"not" => {"any_of" => [{"id" => nil}, {"amount_cents" => {"lt" => 1000}}]}})).to eq []
      end

      it "`equal_to_any_of:` with `nil` matches documents with null values or not null values" do
        index_into(
          graphql,
          widget1 = build(:widget, amount_cents: 1000),
          widget2 = build(:widget, amount_cents: nil),
          widget3 = build(:widget, amount_cents: 2500)
        )

        expect(search_with_filter("amount_cents", "equal_to_any_of", [nil])).to eq ids_of(widget2)
        expect(search_with_filter("amount_cents", "equal_to_any_of", [nil, 2500])).to match_array(ids_of(widget2, widget3))

        inner_not_result1 = search_with_freeform_filter({"amount_cents" => {"not" => {"equal_to_any_of" => [nil]}}})
        outer_not_result1 = search_with_freeform_filter({"not" => {"amount_cents" => {"equal_to_any_of" => [nil]}}})
        expect(inner_not_result1).to eq(outer_not_result1).and match_array(ids_of(widget1, widget3))

        inner_not_result2 = search_with_freeform_filter({"amount_cents" => {"not" => {"equal_to_any_of" => [nil, 1000]}}})
        outer_not_result2 = search_with_freeform_filter({"not" => {"amount_cents" => {"equal_to_any_of" => [nil, 1000]}}})
        expect(inner_not_result2).to eq(outer_not_result2).and eq ids_of(widget3)
      end

      it "`equal_to_any_of:` with `nil` nested within `any_of` matches documents with null values" do
        index_into(
          graphql,
          build(:widget, amount_cents: 1000),
          widget2 = build(:widget, amount_cents: nil),
          build(:widget, amount_cents: 2500)
        )

        expect(
          ids_of(search_datastore(filter:
            {"any_of" => [{"amount_cents" => {"equal_to_any_of" => [nil]}}]}).to_a)
        ).to eq ids_of(widget2)
      end

      describe "`not`" do
        it "negates the inner filter expression" do
          index_into(
            graphql,
            widget1 = build(:widget),
            widget2 = build(:widget),
            widget3 = build(:widget)
          )

          inner_not_result = search_with_freeform_filter({"id" => {"not" => {"equal_to_any_of" => ids_of(widget1, widget3)}}})
          outer_not_result = search_with_freeform_filter({"not" => {"id" => {"equal_to_any_of" => ids_of(widget1, widget3)}}})

          expect(inner_not_result).to eq(outer_not_result).and match_array(ids_of(widget2))
        end

        it "can negate multiple inner filter predicates" do
          index_into(
            graphql,
            widget1 = build(:widget, amount_cents: 100),
            _widget2 = build(:widget, amount_cents: 205),
            widget3 = build(:widget, amount_cents: 400)
          )

          inner_not_result = search_with_freeform_filter({"amount_cents" => {"not" => {
            "gte" => 200,
            "lt" => 300
          }}})

          outer_not_result = search_with_freeform_filter({"not" => {"amount_cents" => {
            "gte" => 200,
            "lt" => 300
          }}})

          expect(inner_not_result).to eq(outer_not_result).and match_array(ids_of(widget1, widget3))
        end

        it "negates a complex compound inner filter expression" do
          index_into(
            graphql,
            widget1 = build(:widget, options: {size: "SMALL", color: "GREEN"}, cost: {currency: "USD", amount_cents: 100}),
            _widget2 = build(:widget, options: {size: "MEDIUM", color: "GREEN"}, cost: {currency: "USD", amount_cents: 200}),
            widget3 = build(:widget, options: {size: "SMALL", color: "RED"}, cost: {currency: "GBP", amount_cents: 200}),
            _widget4 = build(:widget, options: {size: "SMALL", color: "RED"}, cost: {currency: "GBP", amount_cents: 100}),
            widget5 = build(:widget, options: {size: "MEDIUM", color: "RED"}, cost: {currency: "GBP", amount_cents: 200})
          )

          result = search_with_freeform_filter({"not" => {
            "cost" => {
              "any_of" => [
                {"currency" => {"equal_to_any_of" => ["USD"]}},
                {"amount_cents" => {"equal_to_any_of" => [100]}}
              ]
            },
            "options" => {
              "any_of" => [
                {"size" => {"equal_to_any_of" => [size_of("MEDIUM")]}},
                {"color" => {"equal_to_any_of" => [color_of("RED")]}}
              ]
            }
          }})

          expect(result).to match_array(ids_of(widget1, widget3, widget5))
        end

        it "works correctly when included alongside other filtering operators" do
          index_into(
            graphql,
            _widget1 = build(:widget, amount_cents: 100),
            _widget2 = build(:widget, amount_cents: 205),
            widget3 = build(:widget, amount_cents: 400)
          )

          inner_not_result = search_with_freeform_filter({"amount_cents" => {
            "gt" => 200,
            "not" => {"equal_to_any_of" => [205]}
          }})

          outer_not_result = search_with_freeform_filter({
            "amount_cents" => {
              "gt" => 200
            },
            "not" => {
              "amount_cents" => {
                "equal_to_any_of" => [205]
              }
            }
          })

          expect(inner_not_result).to eq(outer_not_result).and match_array(ids_of(widget3))
        end

        it "works correctly when included alongside an `any_of`" do
          index_into(
            graphql,
            widget1 = build(:widget, amount_cents: 100),
            _widget2 = build(:widget, amount_cents: 205),
            _widget3 = build(:widget, amount_cents: 400),
            widget4 = build(:widget, amount_cents: 550)
          )

          inner_not_result = search_with_freeform_filter({"amount_cents" => {
            "not" => {"equal_to_any_of" => [205]},
            "any_of" => [
              {"gt" => 500},
              {"lt" => 300}
            ]
          }})

          outer_not_result = search_with_freeform_filter({
            "not" => {
              "amount_cents" => {"equal_to_any_of" => [205]}
            },
            "amount_cents" => {
              "any_of" => [
                {"gt" => 500},
                {"lt" => 300}
              ]
            }
          })

          expect(inner_not_result).to eq(outer_not_result).and match_array(ids_of(widget1, widget4))
        end

        it "works correctly when `not` is within `any_of`" do
          index_into(
            graphql,
            widget1 = build(:widget, amount_cents: 100),
            widget2 = build(:widget, amount_cents: 205),
            _widget3 = build(:widget, amount_cents: 400),
            widget4 = build(:widget, amount_cents: 550)
          )

          inner_not_result = search_with_freeform_filter({"amount_cents" => {
            "any_of" => [
              {"not" => {"equal_to_any_of" => [400]}},
              {"gt" => 500},
              {"lt" => 300}
            ]
          }})

          outer_not_result = search_with_freeform_filter({
            "not" => {
              "amount_cents" => {"equal_to_any_of" => [400]}
            },
            "amount_cents" => {
              "any_of" => [
                {"gt" => 500},
                {"lt" => 300}
              ]
            }
          })

          expect(inner_not_result).to eq(outer_not_result).and match_array(ids_of(widget1, widget2, widget4))
        end

        it "filters to no documents when filtering to `expression AND NOT (expression)`" do
          index_into(
            graphql,
            _widget1 = build(:widget, amount_cents: 100),
            _widget2 = build(:widget, amount_cents: 205),
            _widget3 = build(:widget, amount_cents: 400)
          )

          inner_not_result = search_with_freeform_filter({"amount_cents" => {
            "equal_to_any_of" => [205],
            "not" => {"equal_to_any_of" => [205]}
          }})

          outer_not_result = search_with_freeform_filter({
            "not" => {
              "amount_cents" => {"equal_to_any_of" => [205]}
            },
            "amount_cents" => {
              "equal_to_any_of" => [205]
            }
          })

          expect(inner_not_result).to eq(outer_not_result).and eq []
        end

        it "handles nested `not`s" do
          index_into(
            graphql,
            widget1 = build(:widget, amount_cents: 100),
            widget2 = build(:widget, amount_cents: 205),
            widget3 = build(:widget, amount_cents: 400)
          )

          inner_not_result = search_with_freeform_filter({"amount_cents" => {
            "not" => {
              "not" => {"equal_to_any_of" => [205]}
            }
          }})

          outer_not_result = search_with_freeform_filter({"not" => {
            "amount_cents" => {
              "not" => {"equal_to_any_of" => [205]}
            }
          }})

          triple_nested_not = search_with_freeform_filter({"amount_cents" => {
            "not" => {
              "not" => {
                "not" => {"equal_to_any_of" => [205]}
              }
            }
          }})

          expect(inner_not_result).to eq(outer_not_result).and match_array(ids_of(widget2))
          expect(triple_nested_not).to match_array(ids_of(widget1, widget3))
        end

        it "matches no documents when set to `nil`" do
          index_into(
            graphql,
            build(:widget, amount_cents: 100),
            build(:widget, amount_cents: 205),
            build(:widget, amount_cents: 400)
          )

          inner_not_result1 = search_with_freeform_filter({"amount_cents" => {
            "not" => nil
          }})

          outer_not_result1 = search_with_freeform_filter({"not" => {
            "amount_cents" => nil
          }})

          inner_not_result2 = search_with_freeform_filter({"amount_cents" => {
            "not" => nil,
            "lt" => 200
          }})

          outer_not_result2 = search_with_freeform_filter({
            "not" => {
              "amount_cents" => nil
            },
            "amount_cents" => {
              "lt" => 200
            }
          })

          inner_not_result3 = search_with_freeform_filter({"amount_cents" => {
            "not" => {"equal_to_any_of" => nil}
          }})

          outer_not_result3 = search_with_freeform_filter({"not" => {
            "amount_cents" => {"equal_to_any_of" => nil}
          }})

          inner_not_result4 = search_with_freeform_filter({"amount_cents" => {
            "not" => {}
          }})

          outer_not_result4 = search_with_freeform_filter({"not" => {
            "amount_cents" => {}
          }})

          expect(inner_not_result1).to eq(outer_not_result1).and eq []
          expect(inner_not_result2).to eq(outer_not_result2).and eq []
          expect(inner_not_result3).to eq(outer_not_result3).and eq []
          expect(inner_not_result4).to eq(outer_not_result4).and eq []
        end

        it "is treated as `true` when set to nil inside `any_of`" do
          index_into(
            graphql,
            widget1 = build(:widget, amount_cents: 100),
            build(:widget, amount_cents: 205),
            build(:widget, amount_cents: 400)
          )

          inner_not_result1 = search_with_freeform_filter({"amount_cents" => {
            "any_of" => [
              {"not" => nil},
              {"lt" => 200}
            ]
          }})

          outer_not_result1 = search_with_freeform_filter({
            "any_of" => [
              {
                "not" => {
                  "amount_cents" => nil
                }
              },
              {
                "amount_cents" => {
                  "lt" => 200
                }
              }
            ]
          })

          expect(inner_not_result1).to eq(outer_not_result1).and match_array(ids_of(widget1))
        end
      end

      def search_with_freeform_filter(filter, **options)
        ids_of(search_datastore(filter: filter, sort: [], **options).to_a)
      end

      def search_with_filter(field, operator, value)
        ids_of(search_datastore(filter: {field => {operator => value}}, sort: []).to_a)
      end

      def enum_value(type_name, value_name)
        graphql.schema.type_named(type_name).enum_value_named(value_name)
      end

      def size_of(value_name)
        enum_value("SizeInput", value_name)
      end

      def color_of(value_name)
        enum_value("ColorInput", value_name)
      end
    end
  end
end
