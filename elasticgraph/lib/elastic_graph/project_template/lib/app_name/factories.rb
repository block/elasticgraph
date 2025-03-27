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

    bio { build(:artist_bio, artistName: name) }

    genres do
      # Available genres from the MusicGenre enum
      all_genres = %w[
        ALTERNATIVE BLUES BLUEGRASS CLASSICAL COUNTRY ELECTRONIC FOLK HIP_HOP
        INDIE JAZZ METAL POP PUNK REGGAE RNB ROCK SKA SOUL
      ]

      # Pick 1-3 random genres
      Faker::Base.sample(all_genres, Faker::Number.between(from: 1, to: 3)).uniq
    end

    albums do
      Faker::Number.between(from: 1, to: 6).times.map { build(:album) }
    end

    tours do
      Faker::Number.between(from: 0, to: 4).times.map do
        song = Faker::Base.sample(albums.flat_map { |a| a.fetch(:tracks).map { |t| t.fetch(:name) } })
        build(:tour, venueIds: venueIds, name: "The #{song} Tour")
      end
    end

    transient do
      venueIds { [] }
    end
  end

  factory :artist_bio, parent: :hash_base do
    __typename { "ArtistBio" }
    yearFormed { Faker::Number.between(from: 1900, to: 2025) }
    homeCountry { Faker::Address.country }
    description do
      # Generate a realistic artist bio by combining multiple sentences
      year = yearFormed

      # Common adjectives for music descriptions
      adjectives = [
        "innovative", "groundbreaking", "distinctive", "masterful", "energetic",
        "soulful", "dynamic", "melodic", "haunting", "powerful", "ethereal",
        "raw", "polished", "intricate", "atmospheric", "intense", "virtuosic"
      ].shuffle

      # Musical elements for variety
      musical_elements = [
        "harmonies", "compositions", "arrangements", "rhythms", "melodies",
        "songwriting", "instrumentation", "productions", "performances", "vocals"
      ].shuffle

      genres = Faker::Base.sample(Faker::Base.translate("faker.music.genres"), 20)
      instruments = Faker::Base.sample(Faker::Base.translate("faker.music.instruments"), 20).map(&:downcase)

      # Origin story variants
      origin = [
        "#{artistName} was formed in #{year} in #{homeCountry}.",
        "Emerging from #{homeCountry}'s #{genres.pop.downcase} scene in #{year}, #{artistName} began their musical journey.",
        "Founded in #{homeCountry} in #{year}, #{artistName} started as a collective of #{genres.pop.downcase} musicians.",
        "The story of #{artistName} began in #{year} when a group of musicians in #{homeCountry} came together."
      ].sample

      # Musical style variants
      style = [
        "Drawing inspiration from #{genres.pop} and #{genres.pop}, they developed a sound featuring #{instruments.pop}, #{instruments.pop}, #{instruments.pop}, and #{instruments.pop}.",
        "Their #{adjectives.pop} style blends elements of #{genres.pop} with #{genres.pop}, creating a unique musical identity centered on their #{adjectives.pop} #{instruments.pop} and #{instruments.pop} counterpoint.",
        "Known for their #{adjectives.pop} #{musical_elements.pop}, they combine #{instruments.pop} and #{instruments.pop} with #{adjectives.pop} #{instruments.pop} and #{adjectives.pop} #{instruments.pop} arrangements.",
        "Their music explores the intersection of #{instruments.pop} #{genres.pop} and #{instruments.pop} #{genres.pop}, highlighted by #{adjectives.pop} #{musical_elements.pop}."
      ].sample

      # Career highlight variants
      highlight_year = year + rand(2..5)
      highlight = [
        "Their breakthrough came with '#{Faker::Music.album}' in #{highlight_year}, which showcased their #{adjectives.pop} style.",
        "The release of '#{Faker::Music.album}' in #{highlight_year} marked a turning point, earning critical acclaim for its #{adjectives.pop} #{musical_elements.pop}.",
        "#{highlight_year} saw the release of their defining work '#{Faker::Music.album}', which demonstrated their #{adjectives.pop} approach to #{musical_elements.pop}.",
        "With the #{adjectives.pop} '#{Faker::Music.album}' in #{highlight_year}, they established themselves as pioneers in #{genres.pop.downcase}."
      ].sample

      # Legacy/impact variants
      legacy = [
        "They continue to influence the music scene with their #{adjectives.pop} approach to #{musical_elements.pop}.",
        "Their #{adjectives.pop} contributions to #{genres.pop.downcase} have left a lasting impact on the genre.",
        "To this day, their #{adjectives.pop} #{musical_elements.pop} continue to inspire new generations of musicians.",
        "They remain celebrated for their #{adjectives.pop} live performances and #{adjectives.pop} #{musical_elements.pop}.",
        "Their influence on #{genres.pop.downcase} endures through their #{adjectives.pop} body of work.",
        "Artists today still draw inspiration from their #{adjectives.pop} approach to #{musical_elements.pop}."
      ].sample

      [origin, style, highlight, legacy].join(" ")
    end

    transient do
      artistName { raise "`artistName` must be provided." }
    end
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
