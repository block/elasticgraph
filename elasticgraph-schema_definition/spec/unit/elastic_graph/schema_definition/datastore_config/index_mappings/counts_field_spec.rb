# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require_relative "index_mappings_spec_support"

module ElasticGraph
  module SchemaDefinition
    RSpec.describe "Datastore config index mappings -- `#{LIST_COUNTS_FIELD}` field" do
      include_context "IndexMappingsSpecSupport"

      it "is omitted when there are no list fields" do
        mapping = index_mapping_for "teams" do |schema|
          # We have an embedded object field to demonstrate that its subfields aren't listed in the counts, either.
          schema.object_type "TeamDetails" do |t|
            t.field "first_year", "Int"
          end

          schema.object_type "Team" do |t|
            t.field "id", "ID!"
            t.field "name", "String"
            t.field "details", "TeamDetails"
            t.index "teams"
          end
        end

        expect(mapping.dig("properties")).to exclude(LIST_COUNTS_FIELD)
      end

      it "defines an integer subfield for each scalar list field" do
        mapping = index_mapping_for "teams" do |schema|
          schema.object_type "Team" do |t|
            t.field "id", "ID!"
            t.field "past_names", "[String!]!" # non-null inside and out
            t.field "home_cities", "[String!]" # non-null inside
            t.field "seasons", "[Int]!" # non-null outside
            t.field "games", "[String]" # nullable inside and out
            t.index "teams"
          end
        end

        expect_list_counts_mappings(mapping, LIST_COUNTS_FIELD, %w[
          past_names
          home_cities
          seasons
          games
        ])
      end

      it "treats a `paginated_collection_field` as a list field since it is indexed that way" do
        mapping = index_mapping_for "teams" do |schema|
          schema.object_type "Team" do |t|
            t.field "id", "ID!"
            t.paginated_collection_field "past_names", "String"
            t.index "teams"
          end
        end

        expect_list_counts_mappings(mapping, LIST_COUNTS_FIELD, %w[past_names])
      end

      it "uses pipe-separated paths for list fields embedded on object fields, since dots get interpreted as object nesting by the datastore" do
        mapping = index_mapping_for "teams" do |schema|
          schema.object_type "TeamHistory" do |t|
            t.field "past_names", "[String!]!"
            t.field "past_home_cities", "[String!]!"
          end

          schema.object_type "Team" do |t|
            t.field "id", "ID!"
            t.field "history1", "TeamHistory"  # nullable
            t.field "history2", "TeamHistory!" # non-null
            t.index "teams"
          end
        end

        expect_list_counts_mappings(mapping, LIST_COUNTS_FIELD, %w[
          history1.past_names
          history1.past_home_cities
          history2.past_names
          history2.past_home_cities
        ])
      end

      it "honors the configured `name_in_index`" do
        mapping = index_mapping_for "teams" do |schema|
          schema.object_type "TeamHistory" do |t|
            t.field "past_names", "[String!]!", name_in_index: "past_names_in_index"
            t.field "past_home_cities", "[String!]!"
          end

          schema.object_type "Team" do |t|
            t.field "id", "ID!"
            t.field "history1", "TeamHistory", name_in_index: "history_in_index"
            t.field "history2", "TeamHistory!" # non-null
            t.index "teams"
          end
        end

        expect_list_counts_mappings(mapping, LIST_COUNTS_FIELD, %w[
          history_in_index.past_names_in_index
          history_in_index.past_home_cities
          history2.past_names_in_index
          history2.past_home_cities
        ])
      end

      it "ignores graphql-only fields" do
        mapping = index_mapping_for "teams" do |schema|
          schema.object_type "TeamHistory" do |t|
            t.field "past_names", "[String!]!", graphql_only: true
            t.field "past_home_cities", "[String!]!"
          end

          schema.object_type "Team" do |t|
            t.field "id", "ID!"
            t.field "history1", "TeamHistory!"
            t.field "history2", "TeamHistory!", graphql_only: true
            t.index "teams"
          end
        end

        expect_list_counts_mappings(mapping, LIST_COUNTS_FIELD, %w[history1.past_home_cities])
      end

      context "when you have a list of embedded objects" do
        it "defines an integer subfield for each field of the embedded object type, recursively, since the datastore will index a flat list of values" do
          mapping = index_mapping_for "teams" do |schema|
            schema.object_type "Team" do |t|
              t.field "id", "ID!"
              t.field "seasons", "[TeamSeason!]!" do |f|
                f.mapping type: "object"
              end
              t.index "teams"
            end

            schema.object_type "TeamSeason" do |t|
              t.field "year", "Int"
              t.field "notes", "[String!]!"
              t.field "players", "[Player!]!" do |f|
                f.mapping type: "object"
              end
            end

            schema.object_type "Player" do |t|
              t.field "name", "String"
              t.field "nicknames", "[String!]!"
            end
          end

          expect_list_counts_mappings(mapping, LIST_COUNTS_FIELD, %w[
            seasons
            seasons.notes
            seasons.players
            seasons.players.name
            seasons.players.nicknames
            seasons.year
          ])
        end
      end

      context "when you have a list of nested objects" do
        it "defines a `#{LIST_COUNTS_FIELD}` subfield for the nested field, plus a separate `#{LIST_COUNTS_FIELD}` field under the nested field for its list fields" do
          mapping = index_mapping_for "teams" do |schema|
            schema.object_type "Team" do |t|
              t.field "id", "ID!"
              t.field "seasons", "[TeamSeason!]!" do |f|
                f.mapping type: "nested"
              end
              t.index "teams"
            end

            schema.object_type "TeamSeason" do |t|
              t.field "year", "Int"
              t.field "notes", "[String!]!"
              t.field "players", "[Player!]!" do |f|
                f.mapping type: "nested"
              end
            end

            schema.object_type "Player" do |t|
              t.field "name", "String"
              t.field "nicknames", "[String!]!"
            end
          end

          expect_list_counts_mappings(mapping, LIST_COUNTS_FIELD, %w[seasons])
          expect_list_counts_mappings(mapping, "seasons.#{LIST_COUNTS_FIELD}", %w[notes players])
          expect_list_counts_mappings(mapping, "seasons.players.#{LIST_COUNTS_FIELD}", %w[nicknames])
        end
      end

      it "lets you use a `nested` list under an `object` list and vice-versa" do
        mapping = index_mapping_for "teams" do |schema|
          schema.object_type "Team" do |t|
            t.field "id", "ID!"
            t.field "current_name", "String"
            t.field "past_names", "[String!]!"
            t.field "current_players", "[Player!]!" do |f|
              f.mapping type: "nested"
            end
            t.field "seasons", "[TeamSeason!]!" do |f|
              f.mapping type: "object"
            end
            t.index "teams"
          end

          schema.object_type "Player" do |t|
            t.field "name", "String"
            t.field "nicknames", "[String!]!"
            t.field "seasons", "[PlayerSeason!]!" do |f|
              f.mapping type: "object"
            end
          end

          schema.object_type "TeamSeason" do |t|
            t.field "year", "Int"
            t.field "notes", "[String!]!"
            t.field "players", "[Player!]!" do |f|
              f.mapping type: "nested"
            end
          end

          schema.object_type "PlayerSeason" do |t|
            t.field "year", "Int"
            t.field "games_played", "Int"
            t.paginated_collection_field "awards", "String"
          end
        end

        expect_list_counts_mappings(mapping, LIST_COUNTS_FIELD, [
          "past_names",
          "current_players", # `current_players` is a nested field so we stop there
          "seasons", # `seasons` is an object field so we include it and its sub-lists
          "seasons.notes",
          "seasons.players",
          "seasons.year"
        ])

        expect_list_counts_mappings(mapping, "current_players.#{LIST_COUNTS_FIELD}", %w[
          nicknames
          seasons
          seasons.awards
          seasons.games_played
          seasons.year
        ])

        expect_list_counts_mappings(mapping, "seasons.players.#{LIST_COUNTS_FIELD}", %w[
          nicknames
          seasons
          seasons.awards
          seasons.games_played
          seasons.year
        ])
      end

      def expect_list_counts_mappings(mapping, path_to_counts_field, list_subpaths)
        mapping_path = "properties.#{path_to_counts_field.gsub(".", ".properties.")}.properties".split(".")
        actual_counts_mapping = mapping.dig(*mapping_path)
        expected_counts_mapping = list_subpaths.to_h do |list_subpath|
          [list_subpath.gsub(".", LIST_COUNTS_FIELD_PATH_KEY_SEPARATOR), {"type" => "integer"}]
        end

        expect(actual_counts_mapping).to eq(expected_counts_mapping)
      end
    end
  end
end
