require "digest/md5"
require "factory_bot"
require "faker"
require_relative "shared_factories"

# TODO: replace the artist/album/tour/venue factories with your own.
FactoryBot.define do
  factory :artist, parent: :indexed_type_base do
    __typename { "Artist" }
    # Prevent multiple artists with the same name by hashing the name to produce the id.
    id { Digest::MD5.hexdigest(name) }

    name { Faker::Music.band }

    lifetimeSales do
      albums.map { |a| a.fetch(:soldUnits) }.sum
    end

    bio { build(:artist_bio) }

    albums do
      Faker::Number.between(from: 1, to: 6).times.map { build(:album) }
    end

    tours do
      Faker::Number.between(from: 0, to: 4).times.map { build(:tour, venueIds: venueIds) }
    end

    transient do
      venueIds { [] }
    end
  end

  factory :artist_bio, parent: :hash_base do
    __typename { "ArtistBio" }
    yearFormed { Faker::Number.between(from: 1900, to: 2025) }
    homeCountry { Faker::Address.country }
    description { Faker::Lorem.paragraphs(number: 3).join("\n\n") }
  end

  factory :album, parent: :hash_base do
    __typename { "Album" }
    name { Faker::Music.album }
    releasedOn { Faker::Date.between(from: "1950-01-01", to: "2025-12-31").iso8601 }
    soldUnits { Faker::Number.between(from: 10000, to: 100_000_000) }
    tracks do
      Faker::Number.between(from: 1, to: 15).times.map do |index|
        build(:album_track, trackNumber: index + 1)
      end
    end
  end

  factory :album_track, parent: :hash_base do
    __typename { "AlbumTrack" }
    name { Faker::Music::RockBand.song }
    trackNumber { Faker::Number.between(from: 1, to: 20) }
    lengthInSeconds { Faker::Number.between(from: 30, to: 1200) }
  end

  factory :tour, parent: :hash_base do
    __typename { "Tour" }
    name { "#{Faker::Music::RockBand.song} Tour" }
    shows do
      start_date = Faker::Date.between(from: "1950-01-01", to: "2025-12-31")

      Faker::Number.between(from: 3, to: 30).times.map do |index|
        venue_id = Faker::Base.sample(venueIds)
        build(:show, date: start_date + index, venueId: venue_id)
      end
    end

    transient do
      venueIds { [] }
    end
  end

  factory :show, parent: :hash_base do
    __typename { "Show" }
    attendance { Faker::Number.between(from: 200, to: 100_000) }
    startedAt { "#{date.iso8601}T#{startTime}" }
    venueId { nil }

    transient do
      date { Faker::Date.between(from: "1950-01-01", to: "2025-12-31") }
      startTime { Faker::Base.sample(%w[19:00:00Z 19:30:00Z 20:00:00Z 20:30:00Z]) }
    end
  end

  factory :venue, parent: :indexed_type_base do
    __typename { "Venue" }

    # Prevent multiple venues with the same name by hashing the name to produce the id.
    id { Digest::MD5.hexdigest(name) }

    name do
      # Some common music venue types
      venue_types = ["Theater", "Arena", "Music Hall", "Stadium", "Opera House", "Amphitheater"]

      city_name = Faker::Address.city
      venue_type = Faker::Base.sample(venue_types)

      "#{city_name} #{venue_type}"
    end

    location { build(:geo_location) }
    capacity { Faker::Number.between(from: 200, to: 100_000) }
  end

  factory :geo_location, parent: :hash_base do
    __typename { "GeoLocation" }
    latitude { Faker::Number.between(from: -90.0, to: 90.0) }
    longitude { Faker::Number.between(from: -180.0, to: 180.0) }
  end
end
