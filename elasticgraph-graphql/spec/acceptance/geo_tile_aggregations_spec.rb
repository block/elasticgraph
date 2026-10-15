# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require_relative "elasticgraph_graphql_acceptance_support"

module ElasticGraph
  RSpec.describe "ElasticGraph::GraphQL--geographic aggregations" do
    include_context "ElasticGraph GraphQL acceptance aggregation support"

    context "with nested geographic records" do
      let(:graphql) do
        build_graphql(schema_definition: ->(schema) do
          schema.object_type "GeoContainer" do |t|
            t.field "id", "ID"
            t.field "records", "[GeoRecord!]!" do |f|
              f.mapping type: "nested"
            end
            t.index "geo_containers"
          end
          schema.object_type "GeoRecord" do |t|
            t.field "location", "GeoLocation"
            t.field "tag", "String"
          end
        end)
      end

      it "groups nested locations and returns conservative count bounds" do
        admin.cluster_configurator.configure_cluster(StringIO.new)
        index_records({"__typename" => "GeoContainer", "__version" => 1, "__json_schema_version" => 1, "id" => "one", "records" => [
          {"location" => {"latitude" => 37.16, "longitude" => -123.04}, "tag" => "a"},
          {"location" => {"latitude" => 37.20, "longitude" => -123.10}, "tag" => "a"},
          {"location" => nil, "tag" => "b"}
        ]})
        response = call_graphql_query(<<~QUERY)
          query {
            geo_container_aggregations {
              nodes {
                sub_aggregations {
                  records {
                    nodes {
                      count_detail { approximate_value exact_value upper_bound }
                      grouped_by {
                        location { as_geo_tile(zoom_level: 8) { x y } }
                        tag
                      }
                    }
                  }
                }
              }
            }
          }
        QUERY
        nodes = response.dig("data", "geo_container_aggregations", "nodes", 0, "sub_aggregations", "records", "nodes")
        expect(nodes).to contain_exactly(
          {"grouped_by" => {"location" => {"as_geo_tile" => {"x" => 40, "y" => 99}}, "tag" => "a"}, "count_detail" => {"approximate_value" => 2, "exact_value" => nil, "upper_bound" => 3}},
          {"grouped_by" => {"location" => {"as_geo_tile" => nil}, "tag" => "b"}, "count_detail" => {"approximate_value" => 1, "exact_value" => nil, "upper_bound" => 3}}
        )
      end
    end

    with_both_casing_forms do
      it "combines tile and term groupings and paginates missing and populated locations in both directions", :expect_search_routing do
        index_records(
          build(:team, league: "MLB", stadium_location: nil),
          build(:team, league: "MLB", stadium_location: build(:geo_location, latitude: 37.16, longitude: -123.04)),
          build(:team, league: "MLB", stadium_location: build(:geo_location, latitude: 37.20, longitude: -123.10)),
          build(:team, league: "MLB", stadium_location: build(:geo_location, latitude: -37.16, longitude: 123.04))
        )
        first = geo_page("first: 1")
        expect(first.fetch("nodes").first).to include("count" => 1, "grouping" => {"league" => "MLB", "position" => {"tile" => nil}})
        expect(first.dig("page", "more")).to be true

        second = geo_page("first: 1, after: #{first.dig("page", "cursor").to_json}")
        tile = second.dig("nodes", 0, "grouping", "position", "tile")
        expect(second.dig("nodes", 0, "count")).to eq(2)
        expect(tile).to include("zoom" => 8, "x" => 40, "y" => 99)
        expect(tile.dig("center", "lat")).to be_within(0.000001).of(37.160317)
        expect(tile.dig("center", "lon")).to eq(-123.046875)
        expect(tile.fetch("bounds")).to include("west" => -123.75, "east" => -122.34375)
        expect(tile.dig("corners", "nw", "lat")).to eq(tile.dig("bounds", "north"))
        expect(tile.dig("corners", "se", "lon")).to eq(tile.dig("bounds", "east"))

        third = geo_page("first: 1, after: #{second.dig("page", "cursor").to_json}")
        expect(third.dig("nodes", 0, "count")).to eq(1)
        expect(third.dig("page", "more")).to be false
        backwards = geo_page("last: 1, before: #{third.dig("page", "start").to_json}")
        expect(backwards.fetch("nodes")).to eq(second.fetch("nodes"))
      end

      it "handles the world tile, default zoom, and locations outside Web Mercator's latitude limits", :expect_search_routing do
        index_records(
          build(:team, stadium_location: build(:geo_location, latitude: 90, longitude: -180)),
          build(:team, stadium_location: build(:geo_location, latitude: -90, longitude: 180))
        )
        default = geo_page("first: 10", zoom_argument: "", group_by_league: false)
        expect(default.fetch("nodes").map { |node| node.dig("grouping", "position", "tile", "zoom") }).to eq([7, 7])
        world = geo_page("first: 10", zoom_argument: "(zoom_level: 0)", group_by_league: false)
        expect(world.fetch("nodes").size).to eq(1)
        expect(world.dig("nodes", 0, "count")).to eq(2)
        expect(world.dig("nodes", 0, "grouping", "position", "tile", "center")).to eq("lat" => 0.0, "lon" => 0.0)
      end

      # Fetches a geographic aggregation page with optional league grouping and zoom selection.
      def geo_page(arguments, zoom_argument: "(zoom_level: 8)", group_by_league: true)
        response = call_graphql_query(<<~QUERY)
          query {
            result: team_aggregations(#{arguments}) {
              page: page_info { more: has_next_page cursor: end_cursor start: start_cursor }
              nodes {
                count
                grouping: grouped_by {
                  #{"league" if group_by_league}
                  position: stadium_location {
                    tile: as_geo_tile#{zoom_argument} {
                      zoom: zoom_level
                      x
                      y
                      center: center_point { lat: latitude lon: longitude }
                      bounds { north south east west }
                      corners {
                        nw: northwest { lat: latitude lon: longitude }
                        se: southeast { lat: latitude lon: longitude }
                      }
                    }
                  }
                }
              }
            }
          }
        QUERY
        response.fetch("data").fetch("result")
      end
    end
  end
end
