# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require_relative "aggregation_resolver_support"
require "elastic_graph/constants"
require "support/graphql"

module ElasticGraph
  class GraphQL
    module Aggregation
      RSpec.describe Resolvers, "for geo tiles" do
        include_context "aggregation resolver support"
        include GraphQLSupport

        it "rejects a malformed tile cursor when comparing it with returned buckets" do
          cursor = DecodedCursor.new({"stadium_location.as_geo_tile" => "8/40"}).encode
          buckets = [{"key" => {"stadium_location.as_geo_tile" => "8/40/99"}, "doc_count" => 1}]

          response = resolve_target_nodes(<<~QUERY, target_buckets: buckets, expect_errors: true)
            target: team_aggregations#{graphql_args(first: 1, before: cursor)} {
              nodes { grouped_by { stadium_location { as_geo_tile(zoom_level: 8) { x } } } }
            }
          QUERY

          expect(response.fetch("errors").first.fetch("message")).to include("Invalid geo tile cursor")
          expect(datastore_client).to have_received(:msearch)
        end

        it "accepts a null tile cursor for the missing-location bucket" do
          cursor = DecodedCursor.new({"stadium_location.as_geo_tile" => nil}).encode
          buckets = [{"key" => {"stadium_location.as_geo_tile" => "8/40/99"}, "doc_count" => 1}]

          nodes = resolve_target_nodes(<<~QUERY, target_buckets: buckets)
            target: team_aggregations#{graphql_args(first: 1, after: cursor)} {
              nodes { grouped_by { stadium_location { as_geo_tile(zoom_level: 8) { x } } } }
            }
          QUERY

          expect(nodes).to eq([{"grouped_by" => {"stadium_location" => {"as_geo_tile" => {"x" => 40}}}}])
        end

        it "uses numeric tile ordering when applying a before cursor locally" do
          cursor = DecodedCursor.new({"stadium_location.as_geo_tile" => "8/215/156"}).encode
          buckets = ["8/40/99", "8/215/156"].map do |key|
            {"key" => {"stadium_location.as_geo_tile" => key}, "doc_count" => 1}
          end

          nodes = resolve_target_nodes(<<~QUERY, target_buckets: buckets)
            target: team_aggregations#{graphql_args(first: 2, before: cursor)} {
              nodes { grouped_by { stadium_location { as_geo_tile(zoom_level: 8) { x } } } }
            }
          QUERY

          expect(nodes).to eq([{"grouped_by" => {"stadium_location" => {"as_geo_tile" => {"x" => 40}}}}])
        end

        it "resolves aliased geographic fields from one tile key and returns null for a missing location" do
          buckets = [
            {"key" => {"position.tile" => nil}, "doc_count" => 1},
            {"key" => {"position.tile" => "8/40/99"}, "doc_count" => 2}
          ]

          nodes = resolve_target_nodes(<<~QUERY, target_buckets: buckets)
            target: team_aggregations {
              nodes {
                count
                grouped_by {
                  position: stadium_location {
                    tile: as_geo_tile(zoom_level: 8) {
                      zoom: zoom_level
                      x
                      y
                      center: map_center_point { latitude longitude }
                      bounds { north south east west }
                      corners {
                        northwest { latitude longitude }
                        northeast { latitude longitude }
                        southwest { latitude longitude }
                        southeast { latitude longitude }
                      }
                    }
                  }
                }
              }
            }
          QUERY

          expect(nodes.first).to eq("count" => 1, "grouped_by" => {"position" => {"tile" => nil}})
          expect(nodes.last.dig("grouped_by", "position", "tile")).to match({
            "zoom" => 8, "x" => 40, "y" => 99,
            "center" => geographic_point(37.160317, -123.046875),
            "bounds" => {"north" => a_value_within(1e-6).of(37.718590), "south" => a_value_within(1e-6).of(36.597889), "east" => -122.34375, "west" => -123.75},
            "corners" => {
              "northwest" => geographic_point(37.718590, -123.75),
              "northeast" => geographic_point(37.718590, -122.34375),
              "southwest" => geographic_point(36.597889, -123.75),
              "southeast" => geographic_point(36.597889, -122.34375)
            }
          })
        end

        it "resolves the map center rather than the arithmetic latitude midpoint" do
          tile = resolve_tile("1/0/0")

          expect(tile.fetch("map_center_point").fetch("latitude")).to be_within(0.01).of(66.51)
          expect((tile.dig("bounds", "north") + tile.dig("bounds", "south")) / 2).to be_within(0.01).of(42.53)
        end

        it "resolves the world tile and all four corners at the polar and antimeridian edges" do
          tile = resolve_tile("0/0/0")

          expect(tile).to match({
            "zoom_level" => 0, "x" => 0, "y" => 0,
            "map_center_point" => geographic_point(0.0, 0.0),
            "bounds" => {"north" => a_value_within(1e-6).of(85.051129), "south" => a_value_within(1e-6).of(-85.051129), "east" => 180.0, "west" => -180.0},
            "corners" => {
              "northwest" => geographic_point(85.051129, -180.0),
              "northeast" => geographic_point(85.051129, 180.0),
              "southwest" => geographic_point(-85.051129, -180.0),
              "southeast" => geographic_point(-85.051129, 180.0)
            }
          })
        end

        it "resolves the highest-zoom tile at the eastern and southern map edges" do
          zoom = GEO_TILE_ZOOM_LEVELS.max
          last = (1 << zoom) - 1

          tile = resolve_tile("#{zoom}/#{last}/#{last}")

          expect(tile).to include("zoom_level" => zoom, "x" => last, "y" => last)
          expect(tile.dig("bounds", "east")).to eq(180.0)
          expect(tile.dig("bounds", "south")).to be_within(1e-6).of(-85.051129)
          expect(tile.dig("bounds", "west")).to be < tile.dig("bounds", "east")
          expect(tile.dig("bounds", "south")).to be < tile.dig("bounds", "north")
        end

        it "rejects a non-numeric datastore tile key rather than returning zero coordinates" do
          expect {
            resolve_tile("8/not-a-number/99")
          }.to raise_error(ArgumentError, /invalid value for Integer/)
        end

        # Matches geographic output through GraphQL without depending on its internal value representation.
        def geographic_point(latitude, longitude)
          {"latitude" => a_value_within(1e-6).of(latitude), "longitude" => a_value_within(1e-6).of(longitude)}
        end

        # Resolves every tile field through the normal GraphQL resolver pipeline.
        def resolve_tile(key)
          zoom = key.split("/").first.to_i
          buckets = [{"key" => {"stadium_location.as_geo_tile" => key}, "doc_count" => 1}]
          nodes = resolve_target_nodes(<<~QUERY, target_buckets: buckets)
            target: team_aggregations {
              nodes {
                grouped_by {
                  stadium_location {
                    as_geo_tile(zoom_level: #{zoom}) {
                      zoom_level x y
                      map_center_point { latitude longitude }
                      bounds { north south east west }
                      corners {
                        northwest { latitude longitude }
                        northeast { latitude longitude }
                        southwest { latitude longitude }
                        southeast { latitude longitude }
                      }
                    }
                  }
                }
              }
            }
          QUERY

          nodes.first.dig("grouped_by", "stadium_location", "as_geo_tile")
        end
      end
    end
  end
end
