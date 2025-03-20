# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/constants"
require "elastic_graph/indexer/operation/update"

module ElasticGraph
  class Indexer
    module Operation
      RSpec.describe CountAccumulator do
        describe "counts indexed on the root document" do
          it "includes counts for each list field" do
            counts = root_counts_for_team_event({"past_names" => ["a", "b", "c"], "seasons_object" => []})

            expect(counts).to include({"past_names" => 3, "seasons_object" => 0})
          end

          it "includes a count of zero for nested subfields which we do not have data for" do
            counts = root_counts_for_team_event({"past_names" => ["a", "b", "c"], "seasons_object" => []})

            expect(counts).to include({
              "current_players_nested" => 0,
              "current_players_object" => 0,
              "current_players_object|name" => 0,
              "current_players_object|nicknames" => 0,
              "current_players_object|seasons_nested" => 0,
              "current_players_object|seasons_object" => 0,
              "current_players_object|seasons_object|awards" => 0,
              "current_players_object|seasons_object|games_played" => 0,
              "current_players_object|seasons_object|year" => 0,
              "details|uniform_colors" => 0,
              "forbes_valuations" => 0,
              "forbes_valuation_moneys_nested" => 0,
              "forbes_valuation_moneys_object" => 0,
              "forbes_valuation_moneys_object|amount_cents" => 0,
              "forbes_valuation_moneys_object|currency" => 0,
              "seasons_nested" => 0,
              "seasons_object|count" => 0,
              "seasons_object|notes" => 0,
              "seasons_object|players_nested" => 0,
              "seasons_object|players_object" => 0,
              "seasons_object|players_object|name" => 0,
              "seasons_object|players_object|nicknames" => 0,
              "seasons_object|players_object|seasons_nested" => 0,
              "seasons_object|players_object|seasons_object" => 0,
              "seasons_object|players_object|seasons_object|awards" => 0,
              "seasons_object|players_object|seasons_object|games_played" => 0,
              "seasons_object|players_object|seasons_object|year" => 0,
              "seasons_object|started_at" => 0,
              "seasons_object|won_games_at" => 0,
              "seasons_object|year" => 0,
              "won_championships_at" => 0
            })
          end

          it "omits the count for list fields which get omitted from the bulk payload" do
            counts = root_counts_for_team_event({"past_names" => ["a", "b", "c"], "unknown_list_field" => []})

            expect(counts).to include({"past_names" => 3})
          end

          it "counts embedded fields, using `#{LIST_COUNTS_FIELD_PATH_KEY_SEPARATOR}` as a path separator" do
            counts = root_counts_for_team_event({"details" => {"uniform_colors" => ["a", "b"]}})

            expect(counts).to include({"details|uniform_colors" => 2})
          end

          it "does not attempt to compute any counts from fields which use specialized index field types that are objects in JSON but have no properties in the mapping" do
            counts = root_counts_for_team_event({"past_names" => ["a", "b", "c"], "stadium_location" => {"latitude" => 47.6, "longitude" => -122.3}})

            expect(counts).to include({"past_names" => 3})
          end

          it "counts lists-of-objects-of-lists when the object is not `nested`" do
            # `seasons` is defined with `type: "object"
            counts = root_counts_for_team_event({"seasons_object" => [
              {"notes" => ["a", "b"]},
              {"notes" => []},
              {"notes" => ["c"]},
              {"notes" => ["d", "e", "f", "g"]}
            ]})

            expect(counts).to include({
              "seasons_object" => 4,
              "seasons_object|notes" => 7 # 2 + 0 + 1 + 4 = 7
            })
          end

          it "only counts the size of a `nested` object list, without considering the counts of its inner lists" do
            counts = root_counts_for_team_event({"current_players_nested" => [
              {"nicknames" => ["a", "b"], "seasons_object" => []},
              {"nicknames" => ["a"], "seasons_object" => []}
            ]})

            expect(counts).to include({"current_players_nested" => 2})
          end

          it "accumulates the count of single valued fields within objects in a list" do
            counts = root_counts_for_team_event({"seasons_object" => [
              {"year" => 2020},
              {"year" => 2021}
            ]})

            expect(counts).to include({
              "seasons_object" => 2,
              "seasons_object|year" => 2
            })
          end

          it "does not count `nil` scalar values" do
            counts = root_counts_for_team_event({"seasons_object" => [
              {"year" => 2020},
              {"year" => 2021},
              {"year" => nil}
            ]})

            expect(counts).to include({
              "seasons_object" => 3,
              "seasons_object|year" => 2
            })
          end

          it "does not count `nil` object values" do
            counts = root_counts_for_team_event({"seasons_object" => [
              {"year" => 2020},
              {"year" => 2021},
              nil
            ]})

            expect(counts).to include({
              "seasons_object" => 2,
              "seasons_object|year" => 2
            })
          end

          it "omits the `__counts` field when processing an indexed type that has no list fields" do
            data = {
              "id" => "abc",
              "name" => "Acme",
              "created_at" => "2023-10-12T00:00:00Z"
            }

            params = script_params_for(data: data, source_type: "Manufacturer", destination_type: "Manufacturer")

            expect(params[LIST_COUNTS_FIELD]).to eq nil
            expect(params["data"]).to exclude(LIST_COUNTS_FIELD)
          end
        end

        describe "counts indexed under a `nested` list field" do # `current_players` is a `nested` list field
          it "counts the list elements on the `nested` documents" do
            counts = current_players_counts_for_team_event({"current_players_nested" => [
              {"nicknames" => ["a", "b"]},
              {"nicknames" => ["c"]}
            ]})

            expect(counts).to match [
              a_hash_including({"nicknames" => 2}),
              a_hash_including({"nicknames" => 1})
            ]
          end

          it "counts embedded lists summing the counts" do
            counts = current_players_counts_for_team_event({"current_players_nested" => [
              {"seasons_object" => [
                {"awards" => ["a", "b"]},
                {"awards" => ["c"]}
              ]},
              {"seasons_object" => [{
                "awards" => []
              }]}
            ]})

            expect(counts).to match [
              a_hash_including({"seasons_object" => 2, "seasons_object|awards" => 3}),
              a_hash_including({"seasons_object" => 1, "seasons_object|awards" => 0})
            ]
          end

          it "does not attempt to count any subfields of a nested object that has no list fields" do
            params = script_params_for_team_event({"forbes_valuation_moneys_nested" => [
              {"currency" => "USD", "amount_cents" => 525},
              {"currency" => "USD", "amount_cents" => 725}
            ]})

            expect(params.dig("data", "forbes_valuation_moneys_nested")).to eq [
              {"currency" => "USD", "amount_cents" => 525},
              {"currency" => "USD", "amount_cents" => 725}
            ]
          end

          def current_players_counts_for_team_event(data)
            script_params_for_team_event(data).dig("data", "current_players_nested").map do |player|
              player.fetch(LIST_COUNTS_FIELD)
            end
          end
        end

        describe "counts indexed under an `object` list field" do # `seasons` is an `object` list field
          it "does not have any indexed counts because the list gets flattened at the root" do
            seasons = seasons_for_team_event({"seasons_object" => [
              {"notes" => ["a", "b"]},
              {"notes" => []}
            ]})

            expect(seasons).to match [
              a_hash_including({"notes" => ["a", "b"]}),
              a_hash_including({"notes" => []})
            ]
          end

          it "still generates a `#{LIST_COUNTS_FIELD}` field on any `nested` list fields under the `object` list field" do
            seasons = seasons_for_team_event({"seasons_object" => [
              {"players_nested" => [
                {"seasons_object" => [
                  {"awards" => ["a", "b", "c"]},
                  {"awards" => ["d", "e"]}
                ]},
                {"seasons_object" => [
                  {"awards" => ["d"]}
                ]}
              ]},
              {"players_nested" => []},
              {"players_nested" => [
                {"seasons_object" => []}
              ]},
              {"players_nested" => [
                {"seasons_object" => [
                  {"awards" => []}
                ]}
              ]}
            ]})

            expect(seasons).to match [
              {"players_nested" => [
                {LIST_COUNTS_FIELD => a_hash_including({"seasons_object" => 2, "seasons_object|awards" => 5}), "seasons_object" => [
                  {"awards" => ["a", "b", "c"]},
                  {"awards" => ["d", "e"]}
                ]},
                {LIST_COUNTS_FIELD => a_hash_including({"seasons_object" => 1, "seasons_object|awards" => 1}), "seasons_object" => [
                  {"awards" => ["d"]}
                ]}
              ]},
              {"players_nested" => []},
              {"players_nested" => [
                {LIST_COUNTS_FIELD => a_hash_including({"seasons_object" => 0}), "seasons_object" => []}
              ]},
              {"players_nested" => [
                {LIST_COUNTS_FIELD => a_hash_including({"seasons_object" => 1, "seasons_object|awards" => 0}), "seasons_object" => [
                  {"awards" => []}
                ]}
              ]}
            ]
          end

          def seasons_for_team_event(data)
            script_params_for_team_event(data).dig("data", "seasons_object")
          end
        end

        context "for a derived indexing operation", :factories do
          it "does not attempt to compute any `#{LIST_COUNTS_FIELD}` because the derived indexing script ignores the `#{LIST_COUNTS_FIELD}` parameter" do
            params = script_params_for(source_type: "Widget", destination_type: "WidgetCurrency", data: {
              "cost_currency_introduced_on" => "1980-01-01",
              "cost_currency_primary_continent" => "North America",
              "tags" => ["t1", "t2"]
            })

            expect(params).to exclude(LIST_COUNTS_FIELD)
          end
        end

        def root_counts_for_team_event(data)
          script_params_for_team_event(data).fetch(LIST_COUNTS_FIELD)
        end

        def script_params_for_team_event(data)
          script_params_for(data: data, source_type: "Team", destination_type: "Team")
        end

        def script_params_for(data:, source_type:, destination_type:, indexer: build_indexer)
          # `league` and `formed_on` are required in `data` because they are used for routing and rollover.
          data = data.merge({"league" => "MLB", "formed_on" => "1950-01-01"})

          destination_index_def = indexer.datastore_core.index_definitions_by_graphql_type.fetch(destination_type).first
          update_target = indexer
            .schema_artifacts
            .runtime_metadata
            .object_types_by_name
            .fetch(source_type)
            .update_targets.find { |ut| ut.type == destination_type }

          update = Update.new(
            event: {"type" => source_type, "record" => data},
            destination_index_def: destination_index_def,
            prepared_record: indexer.record_preparer_factory.for_latest_json_schema_version.prepare_for_index(source_type, data),
            update_target: update_target,
            doc_id: "the-id",
            destination_index_mapping: indexer.schema_artifacts.index_mappings_by_index_def_name.fetch(destination_index_def.name)
          )

          update.to_datastore_bulk.dig(1, :script, :params)
        end
      end
    end
  end
end
