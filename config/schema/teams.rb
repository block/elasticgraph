# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

# These types have been designed to focus on list fields:
# - scalar lists
# - nested object lists
# - embedded object lists
# - multiple levels of lists
# - lists under a singleton object
# - any of the above with an alternate `name_in_index`.
ElasticGraph.define_schema do |schema|
  schema.object_type "TeamDetails" do |t|
    t.field "uniform_colors", "[String!]!"

    # `details.count` isn't really meaningful on our team model here, but we need this field
    # to test that ElasticGraph handles a domain field named `count` even while it offers a
    # `count` operator on list fields.
    t.field schema.state.schema_elements.count, "Int"
  end

  schema.object_type "TeamNestedFields" do |t|
    t.field "forbes_valuation_moneys", "[Money!]!" do |f|
      f.mapping type: "nested"
    end

    t.field "current_players", "[Player!]!" do |f|
      f.mapping type: "nested"
    end

    t.field "seasons", "[TeamSeason!]!", name_in_index: "the_seasons" do |f|
      f.mapping type: "nested"
    end
  end

  schema.object_type "Team" do |t|
    t.root_query_fields plural: "teams"
    t.field "id", "ID!"
    t.field "league", "String"
    t.field "country_code", "ID!"
    t.field "formed_on", "Date"
    t.field "current_name", "String"
    t.field "past_names", "[String!]!"
    t.field "won_championships_at", "[DateTime!]!"
    t.field "details", "TeamDetails"
    t.field "stadium_location", "GeoLocation"
    t.field "forbes_valuations", "[JsonSafeLong!]!"

    t.field "forbes_valuation_moneys_nested", "[Money!]!" do |f|
      f.mapping type: "nested"
    end

    t.field "forbes_valuation_moneys_object", "[Money!]!" do |f|
      f.mapping type: "object"
    end

    t.field "current_players_nested", "[Player!]!" do |f|
      f.mapping type: "nested"
    end

    t.field "current_players_object", "[Player!]!" do |f|
      f.mapping type: "object"
    end

    t.field "seasons_nested", "[TeamSeason!]!" do |f|
      f.mapping type: "nested"
    end

    t.field "seasons_object", "[TeamSeason!]!" do |f|
      f.mapping type: "object"
    end

    t.field "nested_fields", "TeamNestedFields", name_in_index: "the_nested_fields"

    # To exercise an edge case, we need: Two different fields of an object type which both have a `nested` field of the same name.
    # Here we duplicate `nested_fields` as `nested_fields2` to achieve that.
    t.field "nested_fields2", "TeamNestedFields"

    t.index "teams" do |i|
      i.route_with "league"
      i.rollover :yearly, "formed_on"
    end
  end

  schema.object_type "Player" do |t|
    t.field "name", "String"
    t.field "nicknames", "[String!]!"
    t.field "affiliations", "Affiliations!"

    t.field "seasons_nested", "[PlayerSeason!]!" do |f|
      f.mapping type: "nested"
    end

    t.field "seasons_object", "[PlayerSeason!]!" do |f|
      f.mapping type: "object"
    end
  end

  schema.object_type "TeamRecord" do |t|
    t.field "wins", "Int", name_in_index: "win_count"
    t.field "losses", "Int", name_in_index: "loss_count"
    t.field "last_win_on", "Date", name_in_index: "last_win_date"
    t.field "first_win_on", "Date"
  end

  schema.object_type "TeamSeason" do |t|
    t.field "record", "TeamRecord", name_in_index: "the_record"
    t.field "year", "Int"
    t.field "notes", "[String!]!", singular: "note"
    # `details.count` isn't really meaningful on our team model here, but we need this field
    # to test that ElasticGraph handles a domain field named `count` on a list-of-object field
    # even while it also offers a `count` operator on all list fields.
    t.field schema.state.schema_elements.count, "Int"
    t.field "started_at", "DateTime"
    t.field "won_games_at", "[DateTime!]!", singular: "won_game_at"
    t.field "was_shortened", "Boolean"

    t.field "players_nested", "[Player!]!" do |f|
      f.mapping type: "nested"
    end

    t.field "players_object", "[Player!]!" do |f|
      f.mapping type: "object"
    end
  end

  schema.object_type "PlayerSeason" do |t|
    t.field "year", "Int"
    t.field "games_played", "Int"
    t.paginated_collection_field "awards", "String"
  end

  schema.object_type "Sponsorship" do |t|
    t.field "sponsor_id", "ID!"
    t.field "annual_total", "Money!"
  end

  schema.object_type "Affiliations" do |t|
    t.field "sponsorships_nested", "[Sponsorship!]!" do |f|
      f.mapping type: "nested"
    end

    t.field "sponsorships_object", "[Sponsorship!]!" do |f|
      f.mapping type: "object"
    end
  end

  schema.object_type "Sponsor" do |t|
    t.root_query_fields plural: "sponsors"
    t.field "id", "ID!"
    t.field "name", "String"
    t.relates_to_many "affiliated_teams_from_nested", "Team", via: "current_players_nested.affiliations.sponsorships_nested.sponsor_id", dir: :in, singular: "affiliated_team_from_nested"
    t.relates_to_many "affiliated_teams_from_object", "Team", via: "current_players_object.affiliations.sponsorships_object.sponsor_id", dir: :in, singular: "affiliated_team_from_object"

    t.index "sponsors"
  end

  schema.object_type "Country" do |t|
    t.field "id", "ID!"
    t.relates_to_many "teams", "Team", via: "country_code", dir: :in, singular: "team"

    # :nocov: -- only one side of these conditionals is executed in our test suite (but both both are covered by rake tasks)
    t.apollo_key fields: "id" if t.respond_to?(:apollo_key)
    # :nocov:

    # Note: we use `paginated_collection_field` here in order to exercise a case with the Apollo entity resolver and
    # a paginated collection field, which initially yielded an exception.
    t.paginated_collection_field "names", "String" do |f|
      # :nocov: -- only one side of these conditionals is executed in our test suite (but both both are covered by rake tasks)
      f.apollo_external if f.respond_to?(:apollo_external)
      # :nocov:
    end

    t.field "currency", "String" do |f|
      # :nocov: -- only one side of these conditionals is executed in our test suite (but both both are covered by rake tasks)
      f.apollo_external if f.respond_to?(:apollo_external)
      # :nocov:
    end
  end
end
