# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  RSpec.describe "Indexing into list fields", :uses_datastore, :factories, :capture_logs do
    let(:indexer) { build_indexer }

    it "indexes counts of any list fields so we can later use it for filtering" do
      sponsors = Array.new(10) { build(:sponsor) }
      team = build_upsert_event(
        :team,
        id: "t1",
        past_names: ["Pilots", "Sonics", "Rainiers"],
        won_championships_at: [],
        forbes_valuations: [90_000_000],
        details: build(:team_details, uniform_colors: %w[teal blue silver]),
        current_players: [
          build(:player, nicknames: ["The Kid", "JRod"], seasons: [
            build(:player_season, awards: ["MVP", "Rookie of the Year", "Cy Young"]),
            build(:player_season, awards: ["Gold Glove"])
          ], sponsors: sponsors[..4]), # 5 sponsors
          build(:player, nicknames: ["Jerry"], seasons: [
            build(:player_season, awards: ["Silver Slugger"])
          ], sponsors: sponsors[5..6]) # 2 sponsors
        ],
        seasons: [
          build(:team_season, notes: %w[A B C], won_games_at: [], players: [
            build(:player, nicknames: ["Neo"], seasons: [
              build(:player_season, awards: ["MVP"]),
              build(:player_season, awards: ["RoY"])
            ], sponsors: sponsors[7..9]), # 3 sponsors
            build(:player, nicknames: ["Dwight"], seasons: [
              build(:player_season, awards: ["Gold Glove"])
            ], sponsors: sponsors[9..]) # 1 sponsor
          ]),
          # This next team_season has `started_at: nil` so we can verify that the count of those values has one less as a result.
          build(:team_season, notes: %w[D], players: [], won_games_at: [], started_at: nil)
        ],
        sponsors: [build(:sponsor)]
      )

      indexer.processor.process([team], refresh_indices: true)

      team_counts = indexed_team_counts.fetch("t1")

      expect(team_counts.keys).to contain_exactly(
        LIST_COUNTS_FIELD,
        "current_players_nested", "current_players_object",
        "seasons_nested", "seasons_object",
        "the_nested_fields", "nested_fields2"
      )

      expect(team_counts.fetch(LIST_COUNTS_FIELD)).to eq({
        "current_players_nested" => 2,
        "current_players_object" => 2,
        "current_players_object|affiliations" => 2,
        "current_players_object|affiliations|sponsorships_nested" => 7,
        "current_players_object|affiliations|sponsorships_object" => 7,
        "current_players_object|affiliations|sponsorships_object|annual_total" => 7,
        "current_players_object|affiliations|sponsorships_object|annual_total|amount_cents" => 7,
        "current_players_object|affiliations|sponsorships_object|annual_total|currency" => 7,
        "current_players_object|affiliations|sponsorships_object|sponsor_id" => 7,
        "current_players_object|name" => 2,
        "current_players_object|nicknames" => 3,
        "current_players_object|seasons_nested" => 3,
        "current_players_object|seasons_object" => 3,
        "current_players_object|seasons_object|awards" => 5, # 3 + 1 + 1
        "current_players_object|seasons_object|games_played" => 3,
        "current_players_object|seasons_object|year" => 3,
        "details|uniform_colors" => 3,
        "forbes_valuations" => 1,
        "forbes_valuation_moneys_nested" => 1,
        "forbes_valuation_moneys_object" => 1,
        "forbes_valuation_moneys_object|amount_cents" => 1,
        "forbes_valuation_moneys_object|currency" => 1,
        "nested_fields2|current_players" => 2,
        "nested_fields2|forbes_valuation_moneys" => 1,
        "nested_fields2|the_seasons" => 2,
        "past_names" => 3,
        "seasons_nested" => 2,
        "seasons_object" => 2,
        "seasons_object|count" => 2,
        "seasons_object|notes" => 4, # 3 + 1
        "seasons_object|players_nested" => 2, # 2 + 0
        "seasons_object|players_object" => 2, # 2 + 0
        "seasons_object|players_object|affiliations" => 2,
        "seasons_object|players_object|affiliations|sponsorships_nested" => 4,
        "seasons_object|players_object|affiliations|sponsorships_object" => 4,
        "seasons_object|players_object|affiliations|sponsorships_object|annual_total" => 4,
        "seasons_object|players_object|affiliations|sponsorships_object|annual_total|amount_cents" => 4,
        "seasons_object|players_object|affiliations|sponsorships_object|annual_total|currency" => 4,
        "seasons_object|players_object|affiliations|sponsorships_object|sponsor_id" => 4,
        "seasons_object|players_object|name" => 2,
        "seasons_object|players_object|nicknames" => 2,
        "seasons_object|players_object|seasons_nested" => 3,
        "seasons_object|players_object|seasons_object" => 3,
        "seasons_object|players_object|seasons_object|awards" => 3,
        "seasons_object|players_object|seasons_object|games_played" => 3,
        "seasons_object|players_object|seasons_object|year" => 3,
        "seasons_object|started_at" => 1,
        "seasons_object|the_record" => 2,
        "seasons_object|the_record|first_win_on" => 2,
        "seasons_object|the_record|last_win_date" => 2,
        "seasons_object|the_record|loss_count" => 2,
        "seasons_object|the_record|win_count" => 2,
        "seasons_object|was_shortened" => 2,
        "seasons_object|won_games_at" => 0,
        "seasons_object|year" => 2,
        "the_nested_fields|current_players" => 2,
        "the_nested_fields|forbes_valuation_moneys" => 1,
        "the_nested_fields|the_seasons" => 2,
        "won_championships_at" => 0
      })

      expect(team_counts.fetch("current_players_nested")).to eq [
        {
          LIST_COUNTS_FIELD => {
            "affiliations|sponsorships_nested" => 5,
            "affiliations|sponsorships_object" => 5,
            "affiliations|sponsorships_object|annual_total" => 5,
            "affiliations|sponsorships_object|annual_total|amount_cents" => 5,
            "affiliations|sponsorships_object|annual_total|currency" => 5,
            "affiliations|sponsorships_object|sponsor_id" => 5,
            "nicknames" => 2,
            "seasons_nested" => 2,
            "seasons_object" => 2,
            "seasons_object|awards" => 4,
            "seasons_object|games_played" => 2,
            "seasons_object|year" => 2
          },
          "seasons_nested" => [
            {LIST_COUNTS_FIELD => {"awards" => 3}},
            {LIST_COUNTS_FIELD => {"awards" => 1}}
          ]
        },
        {
          LIST_COUNTS_FIELD => {
            "nicknames" => 1,
            "affiliations|sponsorships_nested" => 2,
            "affiliations|sponsorships_object" => 2,
            "affiliations|sponsorships_object|annual_total" => 2,
            "affiliations|sponsorships_object|annual_total|amount_cents" => 2,
            "affiliations|sponsorships_object|annual_total|currency" => 2,
            "affiliations|sponsorships_object|sponsor_id" => 2,
            "seasons_nested" => 1,
            "seasons_object" => 1,
            "seasons_object|awards" => 1,
            "seasons_object|games_played" => 1,
            "seasons_object|year" => 1
          },
          "seasons_nested" => [
            {LIST_COUNTS_FIELD => {"awards" => 1}}
          ]
        }
      ]

      expect(team_counts.fetch("current_players_object")).to eq [
        {
          "seasons_nested" => [
            {LIST_COUNTS_FIELD => {"awards" => 3}},
            {LIST_COUNTS_FIELD => {"awards" => 1}}
          ]
        },
        {
          "seasons_nested" => [
            {LIST_COUNTS_FIELD => {"awards" => 1}}
          ]
        }
      ]

      expect(team_counts.fetch("seasons_nested")).to eq [
        {
          LIST_COUNTS_FIELD => {
            "notes" => 3,
            "players_nested" => 2,
            "players_object" => 2,
            "players_object|affiliations" => 2,
            "players_object|affiliations|sponsorships_nested" => 4,
            "players_object|affiliations|sponsorships_object" => 4,
            "players_object|affiliations|sponsorships_object|annual_total" => 4,
            "players_object|affiliations|sponsorships_object|annual_total|amount_cents" => 4,
            "players_object|affiliations|sponsorships_object|annual_total|currency" => 4,
            "players_object|affiliations|sponsorships_object|sponsor_id" => 4,
            "players_object|name" => 2,
            "players_object|nicknames" => 2,
            "players_object|seasons_nested" => 3,
            "players_object|seasons_object" => 3,
            "players_object|seasons_object|awards" => 3,
            "players_object|seasons_object|games_played" => 3,
            "players_object|seasons_object|year" => 3,
            "won_games_at" => 0
          },
          "players_nested" => [
            {
              LIST_COUNTS_FIELD => {
                "affiliations|sponsorships_nested" => 3,
                "affiliations|sponsorships_object" => 3,
                "affiliations|sponsorships_object|annual_total" => 3,
                "affiliations|sponsorships_object|annual_total|amount_cents" => 3,
                "affiliations|sponsorships_object|annual_total|currency" => 3,
                "affiliations|sponsorships_object|sponsor_id" => 3,
                "nicknames" => 1,
                "seasons_nested" => 2,
                "seasons_object" => 2,
                "seasons_object|awards" => 2,
                "seasons_object|games_played" => 2,
                "seasons_object|year" => 2
              },
              "seasons_nested" => [
                {LIST_COUNTS_FIELD => {"awards" => 1}},
                {LIST_COUNTS_FIELD => {"awards" => 1}}
              ]
            },
            {
              LIST_COUNTS_FIELD => {
                "affiliations|sponsorships_nested" => 1,
                "affiliations|sponsorships_object" => 1,
                "affiliations|sponsorships_object|annual_total" => 1,
                "affiliations|sponsorships_object|annual_total|amount_cents" => 1,
                "affiliations|sponsorships_object|annual_total|currency" => 1,
                "affiliations|sponsorships_object|sponsor_id" => 1,
                "nicknames" => 1,
                "seasons_nested" => 1,
                "seasons_object" => 1,
                "seasons_object|awards" => 1,
                "seasons_object|games_played" => 1,
                "seasons_object|year" => 1
              },
              "seasons_nested" => [
                {LIST_COUNTS_FIELD => {"awards" => 1}}
              ]
            }
          ],
          "players_object" => [
            {
              "seasons_nested" => [
                {LIST_COUNTS_FIELD => {"awards" => 1}},
                {LIST_COUNTS_FIELD => {"awards" => 1}}
              ]
            },
            {
              "seasons_nested" => [
                {LIST_COUNTS_FIELD => {"awards" => 1}}
              ]
            }
          ]
        },
        {
          LIST_COUNTS_FIELD => {
            "notes" => 1,
            "players_nested" => 0,
            "players_object" => 0,
            "players_object|affiliations" => 0,
            "players_object|affiliations|sponsorships_nested" => 0,
            "players_object|affiliations|sponsorships_object" => 0,
            "players_object|affiliations|sponsorships_object|annual_total" => 0,
            "players_object|affiliations|sponsorships_object|annual_total|amount_cents" => 0,
            "players_object|affiliations|sponsorships_object|annual_total|currency" => 0,
            "players_object|affiliations|sponsorships_object|sponsor_id" => 0,
            "players_object|name" => 0,
            "players_object|nicknames" => 0,
            "players_object|seasons_nested" => 0,
            "players_object|seasons_object" => 0,
            "players_object|seasons_object|awards" => 0,
            "players_object|seasons_object|games_played" => 0,
            "players_object|seasons_object|year" => 0,
            "won_games_at" => 0
          }
        }
      ]

      expect(team_counts.fetch("seasons_object")).to eq [
        {
          "players_nested" => [
            {
              LIST_COUNTS_FIELD => {
                "affiliations|sponsorships_nested" => 3,
                "affiliations|sponsorships_object" => 3,
                "affiliations|sponsorships_object|annual_total" => 3,
                "affiliations|sponsorships_object|annual_total|amount_cents" => 3,
                "affiliations|sponsorships_object|annual_total|currency" => 3,
                "affiliations|sponsorships_object|sponsor_id" => 3,
                "nicknames" => 1,
                "seasons_nested" => 2,
                "seasons_object" => 2,
                "seasons_object|awards" => 2,
                "seasons_object|games_played" => 2,
                "seasons_object|year" => 2
              },
              "seasons_nested" => [
                {LIST_COUNTS_FIELD => {"awards" => 1}},
                {LIST_COUNTS_FIELD => {"awards" => 1}}
              ]
            },
            {
              LIST_COUNTS_FIELD => {
                "affiliations|sponsorships_nested" => 1,
                "affiliations|sponsorships_object" => 1,
                "affiliations|sponsorships_object|annual_total" => 1,
                "affiliations|sponsorships_object|annual_total|amount_cents" => 1,
                "affiliations|sponsorships_object|annual_total|currency" => 1,
                "affiliations|sponsorships_object|sponsor_id" => 1,
                "nicknames" => 1,
                "seasons_nested" => 1,
                "seasons_object" => 1,
                "seasons_object|awards" => 1,
                "seasons_object|games_played" => 1,
                "seasons_object|year" => 1
              },
              "seasons_nested" => [
                {LIST_COUNTS_FIELD => {"awards" => 1}}
              ]
            }
          ],
          "players_object" => [
            {
              "seasons_nested" => [
                {LIST_COUNTS_FIELD => {"awards" => 1}},
                {LIST_COUNTS_FIELD => {"awards" => 1}}
              ]
            },
            {
              "seasons_nested" => [
                {LIST_COUNTS_FIELD => {"awards" => 1}}
              ]
            }
          ]
        },
        {}
      ]

      expect(team_counts.fetch("the_nested_fields")).to eq({
        "current_players" => [
          {
            "__counts" => {
              "affiliations|sponsorships_nested" => 5,
              "affiliations|sponsorships_object" => 5,
              "affiliations|sponsorships_object|annual_total" => 5,
              "affiliations|sponsorships_object|annual_total|amount_cents" => 5,
              "affiliations|sponsorships_object|annual_total|currency" => 5,
              "affiliations|sponsorships_object|sponsor_id" => 5,
              "nicknames" => 2,
              "seasons_nested" => 2,
              "seasons_object" => 2,
              "seasons_object|awards" => 4,
              "seasons_object|games_played" => 2,
              "seasons_object|year" => 2
            },
            "seasons_nested" => [
              {"__counts" => {"awards" => 3}},
              {"__counts" => {"awards" => 1}}
            ]
          },
          {
            "__counts" => {
              "nicknames" => 1,
              "affiliations|sponsorships_nested" => 2,
              "affiliations|sponsorships_object" => 2,
              "affiliations|sponsorships_object|annual_total" => 2,
              "affiliations|sponsorships_object|annual_total|amount_cents" => 2,
              "affiliations|sponsorships_object|annual_total|currency" => 2,
              "affiliations|sponsorships_object|sponsor_id" => 2,
              "seasons_nested" => 1,
              "seasons_object" => 1,
              "seasons_object|awards" => 1,
              "seasons_object|games_played" => 1,
              "seasons_object|year" => 1
            },
            "seasons_nested" => [
              {"__counts" => {"awards" => 1}}
            ]
          }
        ],
        "the_seasons" => [
          {
            "__counts" => {
              "notes" => 3,
              "players_nested" => 2,
              "players_object" => 2,
              "players_object|affiliations" => 2,
              "players_object|affiliations|sponsorships_nested" => 4,
              "players_object|affiliations|sponsorships_object" => 4,
              "players_object|affiliations|sponsorships_object|annual_total" => 4,
              "players_object|affiliations|sponsorships_object|annual_total|amount_cents" => 4,
              "players_object|affiliations|sponsorships_object|annual_total|currency" => 4,
              "players_object|affiliations|sponsorships_object|sponsor_id" => 4,
              "players_object|name" => 2,
              "players_object|nicknames" => 2,
              "players_object|seasons_nested" => 3,
              "players_object|seasons_object" => 3,
              "players_object|seasons_object|awards" => 3,
              "players_object|seasons_object|games_played" => 3,
              "players_object|seasons_object|year" => 3,
              "won_games_at" => 0
            },
            "players_nested" => [
              {
                "__counts" => {
                  "affiliations|sponsorships_nested" => 3,
                  "affiliations|sponsorships_object" => 3,
                  "affiliations|sponsorships_object|annual_total" => 3,
                  "affiliations|sponsorships_object|annual_total|amount_cents" => 3,
                  "affiliations|sponsorships_object|annual_total|currency" => 3,
                  "affiliations|sponsorships_object|sponsor_id" => 3,
                  "nicknames" => 1,
                  "seasons_nested" => 2,
                  "seasons_object" => 2,
                  "seasons_object|awards" => 2,
                  "seasons_object|games_played" => 2,
                  "seasons_object|year" => 2
                },
                "seasons_nested" => [
                  {"__counts" => {"awards" => 1}},
                  {"__counts" => {"awards" => 1}}
                ]
              },
              {
                "__counts" => {
                  "affiliations|sponsorships_nested" => 1,
                  "affiliations|sponsorships_object" => 1,
                  "affiliations|sponsorships_object|annual_total" => 1,
                  "affiliations|sponsorships_object|annual_total|amount_cents" => 1,
                  "affiliations|sponsorships_object|annual_total|currency" => 1,
                  "affiliations|sponsorships_object|sponsor_id" => 1,
                  "nicknames" => 1,
                  "seasons_nested" => 1,
                  "seasons_object" => 1,
                  "seasons_object|awards" => 1,
                  "seasons_object|games_played" => 1,
                  "seasons_object|year" => 1
                },
                "seasons_nested" => [
                  {"__counts" => {"awards" => 1}}
                ]
              }
            ],
            "players_object" => [
              {
                "seasons_nested" => [
                  {"__counts" => {"awards" => 1}},
                  {"__counts" => {"awards" => 1}}
                ]
              },
              {
                "seasons_nested" => [
                  {"__counts" => {"awards" => 1}}
                ]
              }
            ]
          },
          {
            "__counts" => {
              "notes" => 1,
              "players_nested" => 0,
              "players_object" => 0,
              "players_object|affiliations" => 0,
              "players_object|affiliations|sponsorships_nested" => 0,
              "players_object|affiliations|sponsorships_object" => 0,
              "players_object|affiliations|sponsorships_object|annual_total" => 0,
              "players_object|affiliations|sponsorships_object|annual_total|amount_cents" => 0,
              "players_object|affiliations|sponsorships_object|annual_total|currency" => 0,
              "players_object|affiliations|sponsorships_object|sponsor_id" => 0,
              "players_object|name" => 0,
              "players_object|nicknames" => 0,
              "players_object|seasons_nested" => 0,
              "players_object|seasons_object" => 0,
              "players_object|seasons_object|awards" => 0,
              "players_object|seasons_object|games_played" => 0,
              "players_object|seasons_object|year" => 0,
              "won_games_at" => 0
            }
          }
        ]
      })
    end

    def indexed_team_counts
      main_datastore_client.msearch(body: [{index: "teams_rollover__*"}, {}]).dig("responses", 0, "hits", "hits").to_h do |hit|
        [hit.fetch("_id"), get_counts_from(hit.fetch("_source"))]
      end
    end

    def get_counts_from(hash)
      hash.filter_map do |key, value|
        if key == LIST_COUNTS_FIELD
          [key, value]
        elsif value.is_a?(::Array) && value.first.is_a?(::Hash)
          mapped_values = value.map { |v| get_counts_from(v) }
          [key, mapped_values] unless mapped_values.all?(&:empty?)
        elsif value.is_a?(::Hash) && (sub_counts = get_counts_from(value)).any?
          [key, sub_counts]
        end
      end.to_h
    end
  end
end
