# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/constants"
require "elastic_graph/graphql/aggregation/resolvers/geo_tile"
require "elastic_graph/graphql/schema"

module ElasticGraph
  class GraphQL
    module Aggregation
      module Resolvers
        RSpec.describe GeoTile do
          let(:schema) { instance_double(Schema) }

          it "resolves XYZ coordinates, projected center, bounds, and all four corners" do
            tile = GeoTile.from_key(schema, "8/40/99")
            expect([tile.zoom_level, tile.x, tile.y]).to eq([8, 40, 99])
            expect(tile.center_point).to include("lat" => be_within(0.000001).of(37.160317), "lon" => -123.046875)
            bounds = tile.bounds
            expect(bounds.north).to be_within(0.000001).of(37.718590)
            expect(bounds.south).to be_within(0.000001).of(36.597889)
            expect(bounds.west).to eq(-123.75)
            expect(bounds.east).to eq(-122.34375)
            expect(tile.corners.northwest).to eq("lat" => bounds.north, "lon" => bounds.west)
            expect(tile.corners.northeast).to eq("lat" => bounds.north, "lon" => bounds.east)
            expect(tile.corners.southwest).to eq("lat" => bounds.south, "lon" => bounds.west)
            expect(tile.corners.southeast).to eq("lat" => bounds.south, "lon" => bounds.east)
          end

          it "uses the projected center, not the arithmetic latitude midpoint" do
            tile = GeoTile.from_key(schema, "1/0/0")
            expect(tile.center_point.fetch("lat")).to be_within(0.01).of(66.51)
            expect((tile.bounds.north + tile.bounds.south) / 2).to be_within(0.01).of(42.53)
          end

          it "handles the world tile and both antimeridian and polar edges" do
            world = GeoTile.from_key(schema, "0/0/0")
            expect(world.center_point).to eq("lat" => 0.0, "lon" => 0.0)
            expect(world.bounds.west).to eq(-180.0)
            expect(world.bounds.east).to eq(180.0)
            expect(world.bounds.north).to be_within(0.000001).of(85.051129)
            expect(world.bounds.south).to be_within(0.000001).of(-85.051129)
            zoom = GEO_TILE_ZOOM_LEVELS.max
            last_coordinate = (1 << zoom) - 1
            edge = GeoTile.from_key(schema, "#{zoom}/#{last_coordinate}/#{last_coordinate}")
            expect(edge.bounds.east).to eq(180.0)
            expect(edge.bounds.south).to be_within(0.000001).of(-85.051129)
            expect(edge.bounds.west).to be < edge.bounds.east
            expect(edge.bounds.south).to be < edge.bounds.north
          end

          it "rejects non-numeric coordinates instead of silently treating them as zero" do
            expect { GeoTile.from_key(schema, "8/not-a-number/99") }.to raise_error(ArgumentError)
          end
        end
      end
    end
  end
end
