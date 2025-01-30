# Copyright 2024 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

ElasticGraph.define_schema do |schema|
  schema.object_type "Artist" do |t|
    t.field "id", "ID"
    t.field "name", "String"
    t.field "lifetimeSales", "Int"
    t.field "bio", "ArtistBio"

    t.field "albums", "[Album!]!" do |f|
      f.mapping type: "nested"
    end

    t.field "tours", "[Tour!]!" do |f|
      f.mapping type: "nested"
    end

    t.index "artists"
  end

  schema.object_type "ArtistBio" do |t|
    t.field "yearFormed", "Int"
    t.field "homeCountry", "String"
    t.field "description", "String" do |f|
      f.mapping type: "text"
    end
  end

  schema.object_type "Album" do |t|
    t.field "name", "String"
    t.field "releasedOn", "Date"
    t.field "soldUnits", "Int"
    t.field "tracks", "[AlbumTrack!]!" do |f|
      f.mapping type: "nested"
    end
  end

  schema.object_type "AlbumTrack" do |t|
    t.field "name", "String"
    t.field "trackNumber", "Int"
    t.field "lengthInSeconds", "Int"
  end

  schema.object_type "Tour" do |t|
    t.field "name", "String"
    t.field "shows", "[Show!]!" do |f|
      f.mapping type: "nested"
    end
  end

  schema.object_type "Show" do |t|
    t.relates_to_one "venue", "Venue", via: "venueId", dir: :out
    t.field "attendance", "Int"
    t.field "startedAt", "DateTime"
  end

  schema.object_type "Venue" do |t|
    t.field "id", "ID"
    t.field "name", "String"
    t.field "location", "GeoLocation"
    t.field "capacity", "Int"
    t.relates_to_many "featuredArtists", "Artist", via: "tours.shows.venueId", dir: :in, singular: "featuredArtist"

    t.index "venues"
  end
end
