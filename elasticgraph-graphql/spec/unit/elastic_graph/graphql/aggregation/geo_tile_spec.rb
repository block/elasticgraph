# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphql/aggregation/geo_tile"
require "elastic_graph/schema_artifacts/runtime_metadata/schema_element_names"

module ElasticGraph
  class GraphQL
    module Aggregation
      RSpec.describe GeoTile do
        let(:names) { SchemaArtifacts::RuntimeMetadata::SchemaElementNames.new(form: :camelCase) }

        it "decodes XYZ coordinates, projected center, bounds, and corners" do
          tile = GeoTile.decode("8/40/99", names: names)
          expect(tile).to include("zoomLevel" => 8, "x" => 40, "y" => 99)
          expect(tile.fetch("centerPoint")).to include("lat" => be_within(0.000001).of(37.160317), "lon" => -123.046875)
          expect(tile.fetch("bounds")).to include(
            "north" => be_within(0.000001).of(37.718590), "south" => be_within(0.000001).of(36.597889),
            "west" => -123.75, "east" => -122.34375
          )
          bounds = tile.fetch("bounds")
          expect(tile.fetch("corners")).to eq({
            "northWest" => {"lat" => bounds.fetch("north"), "lon" => bounds.fetch("west")},
            "northEast" => {"lat" => bounds.fetch("north"), "lon" => bounds.fetch("east")},
            "southWest" => {"lat" => bounds.fetch("south"), "lon" => bounds.fetch("west")},
            "southEast" => {"lat" => bounds.fetch("south"), "lon" => bounds.fetch("east")}
          })
        end

        it "uses the projected center, not the arithmetic latitude midpoint" do
          tile = GeoTile.decode("1/0/0", names: names)
          expect(tile.dig("centerPoint", "lat")).to be_within(0.01).of(66.51)
          expect((tile.dig("bounds", "north") + tile.dig("bounds", "south")) / 2).to be_within(0.01).of(42.53)
        end

        it "handles the world tile and both antimeridian and polar edges" do
          world = GeoTile.decode("0/0/0", names: names)
          expect(world.fetch("centerPoint")).to eq("lat" => 0.0, "lon" => 0.0)
          expect(world.fetch("bounds")).to include("west" => -180.0, "east" => 180.0, "north" => be_within(0.000001).of(85.051129), "south" => be_within(0.000001).of(-85.051129))
          edge = GeoTile.decode("29/536870911/536870911", names: names)
          expect(edge.dig("bounds", "east")).to eq(180.0)
          expect(edge.dig("bounds", "south")).to be_within(0.000001).of(-85.051129)
          expect(edge.dig("bounds", "west")).to be < edge.dig("bounds", "east")
          expect(edge.dig("bounds", "south")).to be < edge.dig("bounds", "north")
        end

        it "honors schema casing and overridden field names" do
          names = SchemaArtifacts::RuntimeMetadata::SchemaElementNames.new(form: :snake_case, overrides: {center_point: "middle", zoom_level: "zoom", north_west: "nw"})
          tile = GeoTile.decode("8/40/99", names: names)
          expect(tile).to include("zoom" => 8, "middle" => include("lat", "lon"))
          expect(tile.fetch("corners")).to include("nw", "south_east")
        end
      end
    end
  end
end
