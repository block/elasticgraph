# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "date"
require "time"
require "elastic_graph/spec_support/factories/shared"

# Note: it is *essential* that all factories defined here generate records
# deterministically, in order for the request bodies to (and responses from)
# the dataastore to not change between VCR cassettes being recorded and replayed.

# Note: in our JSON Schema, `__typename` is defined for ALL object types but is only _required_ on abstract object types
# (e.g. for type unions or interfaces). However, clients that publish using egpublisher always include it on every object
# type (because of how the code gen works).
#
# In addition, in the factories here we require it on all indexed types (the ones with `parent: :graph_base`) because
# `Indexer::TestSupport::Converters.upsert_event_for` relies on it in order to build the event envelope. That process strips the
# `__typename` from the `record`.
#
# We intentionally include `__typename` in many non-indexed object types here in order to simulate it being set on them
# (since that's what our publishers do) in order to exercise edge cases related to `__typename`. However, we haven't
# included it in all object types since some publishers could omit it.

awards = ["MVP", "Rookie of the Year", "Gold Glove", "Cy Young", "Silver Slugger", "Humanitarian", "Biggest Jerk"]
leagues = %w[MLB NBA NFL NHL MLS NCAA OfNations]

# A fixed date we can use instead of `Date.today` in our factories.
# As mentioned above, our factories are intended to be deterministic, and we need to avoid using `Date.today` (or `Time.now`) to
# ensure determinism.
recent_date = ::Date.new(2023, 11, 25)

FactoryBot.define do
  factory :team, parent: :indexed_type do
    __typename { "Team" }
    league { Faker::Base.sample(leagues) }
    # Limit `formed_on` to a 5 year stretch so that we don't make too many indices in our test environment since `teams` uses a yearly rollover index.
    formed_on { Faker::Date.between(from: recent_date - (5 * 365), to: recent_date - 365).iso8601 }
    current_name { Faker::Team.name }
    details { build :team_details }
    stadium_location { build :geo_location }
    country_code { Faker::Address.country_code }

    past_names do
      Array.new(Faker::Number.between(from: 0, to: 3)) { Faker::Team.name } - [current_name]
    end

    won_championships_at do
      Array.new(Faker::Number.between(from: 0, to: 3)) do
        Faker::Time.between(from: recent_date - 30, to: recent_date).utc.iso8601
      end
    end

    forbes_valuations do
      Array.new(Faker::Number.between(from: 1, to: 4)) do
        Faker::Number.between(from: 10, to: 50000) * 10_000
      end
    end

    forbes_valuation_moneys_nested { forbes_valuations.map { |v| build(:money, amount_cents: v, currency: "USD") } }
    forbes_valuation_moneys_object { forbes_valuation_moneys_nested }

    current_players_nested { current_players }
    current_players_object { current_players }
    seasons_nested { seasons }
    seasons_object { seasons }

    nested_fields do
      {
        current_players: current_players_nested,
        forbes_valuation_moneys: forbes_valuation_moneys_nested,
        seasons: seasons_nested
      }
    end

    nested_fields2 { nested_fields }

    transient do
      sponsors { [] }
      current_players do
        Array.new(Faker::Number.between(from: 2, to: 8)) { build :player, sponsors: sponsors }
      end

      seasons do
        Array.new(Faker::Number.between(from: 2, to: 5)) { build :team_season }.uniq { |h| h.fetch(:year) }
      end
    end
  end

  factory :team_details, parent: :hash_base do
    uniform_colors do
      Array.new(Faker::Base.sample([2, 3])) { Faker::Color.color_name }.uniq
    end

    count { Faker::Number.between(from: 0, to: 100) }
  end

  factory :player, parent: :hash_base do
    __typename { "Player" }
    name { Faker::Name.name }

    nicknames do
      Array.new(Faker::Number.between(from: 0, to: 3)) { Faker::FunnyName.name }
    end

    seasons_nested { seasons }
    seasons_object { seasons }

    affiliations { build :affiliations, sponsors: sponsors }

    transient do
      sponsors { [] }
      seasons do
        Array.new(Faker::Number.between(from: 0, to: 3)) { build :player_season }.uniq { |h| h.fetch(:year) }
      end
    end
  end

  factory :team_record, parent: :hash_base do
    wins { Faker::Number.between(from: 0, to: 100) }
    losses { Faker::Number.between(from: 0, to: 100) }
    first_win_on { first_win_on_date.iso8601 }
    last_win_on { (first_win_on_date + 120).iso8601 }

    transient do
      first_win_on_date { Faker::Date.between(from: recent_date - 3650, to: recent_date - 200) }
    end
  end

  factory :team_season, parent: :hash_base do
    __typename { "TeamSeason" }
    year { Faker::Number.between(from: 1950, to: 2023) }
    record { build :team_record }
    was_shortened { false }

    notes do
      Array.new(Faker::Number.between(from: 1, to: 3)) { Faker::TvShows::MichaelScott.quote }
    end

    count { Faker::Number.between(from: 0, to: 100) }

    players_nested { players }
    players_object { players }

    started_at { Faker::Time.between(from: start_of_year, to: end_of_year).utc.iso8601 }

    won_games_at do
      started_at_time = ::Time.iso8601(started_at)
      Array.new(Faker::Number.between(from: 2, to: 5)) do
        Faker::Time.between(from: started_at_time, to: end_of_year).utc.iso8601
      end
    end

    transient do
      players do
        Array.new(Faker::Number.between(from: 2, to: 8)) { build :player }
      end

      start_of_year { ::Time.iso8601("#{year}-01-01T00:00:00Z") }
      end_of_year { ::Time.iso8601("#{year}-12-31T23:59:59.999Z") }
    end
  end

  factory :player_season, parent: :hash_base do
    __typename { "PlayerSeason" }
    year { Faker::Number.between(from: 1950, to: 2023) }
    games_played { Faker::Number.between(from: 1, to: 162) }

    awards do
      Array.new(Faker::Number.between(from: 0, to: 3)) { Faker::Base.sample(awards) }.uniq
    end
  end

  factory :affiliations, parent: :hash_base do
    sponsorships_nested { sponsorships }
    sponsorships_object { sponsorships }
    transient do
      sponsors { [] }
      sponsorships do
        sponsors.map { |sponsor| build(:sponsorship, sponsor: sponsor) }
      end
    end
  end

  factory :sponsorship, parent: :hash_base do
    __typename { "Sponsorship" }
    annual_total { build :money, amount_cents: Faker::Number.between(from: 10, to: 50000) * 10_000, currency: "USD" }
    sponsor_id { sponsor.fetch(:id) }

    transient do
      sponsor { [] }
    end
  end

  factory :sponsor, parent: :indexed_type do
    __typename { "Sponsor" }
    name { Faker::Company.name }
  end
end
