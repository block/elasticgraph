# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require_relative "aggregation_resolver_support"

module ElasticGraph
  class GraphQL
    module Aggregation
      RSpec.describe Resolvers, "for geo tiles" do
        include_context "aggregation resolver support"

        it "rejects a malformed tile cursor when comparing it with returned buckets" do
          cursor = DecodedCursor.new({"stadium_location.as_geo_tile" => "8/40"}).encode
          buckets = [{"key" => {"stadium_location.as_geo_tile" => "8/40/99"}, "doc_count" => 1}]
          response = resolve_target_nodes(<<~QUERY, target_buckets: buckets, expect_errors: true)
            target: team_aggregations(first: 1, before: #{cursor.to_json}) {
              nodes { grouped_by { stadium_location { as_geo_tile(zoom_level: 8) { x } } } }
            }
          QUERY
          expect(response.fetch("errors").first.fetch("message")).to include("Invalid geo tile cursor")
          expect(datastore_client).to have_received(:msearch)
        end

        it "accepts a null tile cursor for the missing-location bucket" do
          cursor = DecodedCursor.new({"stadium_location.as_geo_tile" => nil}).encode
          nodes = resolve_target_nodes(<<~QUERY, target_buckets: [{"key" => {"stadium_location.as_geo_tile" => "8/40/99"}, "doc_count" => 1}])
            target: team_aggregations(first: 1, after: #{cursor.to_json}) {
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
            target: team_aggregations(first: 2, before: #{cursor.to_json}) {
              nodes { grouped_by { stadium_location { as_geo_tile(zoom_level: 8) { x } } } }
            }
          QUERY
          expect(nodes).to eq([{"grouped_by" => {"stadium_location" => {"as_geo_tile" => {"x" => 40}}}}])
        end

        it "resolves aliased tile objects and missing locations without extending the grouping path" do
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
                      center: center_point { lat: latitude lon: longitude }
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
          tile = nodes.last.dig("grouped_by", "position", "tile")
          expect(tile).to include("zoom" => 8, "x" => 40, "y" => 99, "center" => {"lat" => be_within(0.000001).of(37.160317), "lon" => -123.046875})
          expect(tile.fetch("corners").fetch("northwest")).to eq("latitude" => tile.dig("bounds", "north"), "longitude" => tile.dig("bounds", "west"))
        end
      end
    end
  end
end
