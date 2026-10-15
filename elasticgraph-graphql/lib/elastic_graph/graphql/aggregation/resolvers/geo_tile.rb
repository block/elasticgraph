# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphql/resolvers/resolvable_value"

module ElasticGraph
  class GraphQL
    module Aggregation
      module Resolvers
        # Resolves datastore tile keys into geographic representations using
        # [Web Mercator XYZ coordinates](https://wiki.openstreetmap.org/wiki/Slippy_map_tilenames).
        # The inverse formulas follow [Elasticsearch's GeoTileUtils](https://github.com/elastic/elasticsearch/blob/36a8b81764d3448666ad213c3b47762e5fa22d42/server/src/main/java/org/elasticsearch/search/aggregations/bucket/geogrid/GeoTileUtils.java)
        # (`toBoundingBox` and `zxyToGeoPoint`).
        # [OpenSearch's GeoTileUtils](https://github.com/opensearch-project/OpenSearch/blob/d016718b1718659f39d1e587a33fad5dc54fd711/server/src/main/java/org/opensearch/search/aggregations/bucket/GeoTileUtils.java)
        # uses the same formulas.
        #
        # Below zoom level 20, our values match apart from small differences caused by the datastores'
        # approximate sinh/atan functions. At zoom level 20 and above, Elasticsearch snaps latitude bounds
        # to Lucene's coordinate grid. We retain the unsnapped values; the difference is less than 1 cm.
        class GeoTile < GraphQL::Resolvers::ResolvableValue.new(:zoom_level, :x, :y)
          # Builds a tile from the datastore's zoom/x/y key, rejecting non-numeric coordinates.
          def self.from_key(schema, key)
            zoom_level, x, y = key.split("/").map { |part| Integer(part) } # : [::Integer, ::Integer, ::Integer]
            new(schema, zoom_level, x, y)
          end

          # Resolves the projected center using GeoLocation's indexed lat/lon field names.
          def center_point
            {"lat" => latitude(y + 0.5), "lon" => longitude(x + 0.5)}
          end

          # Calculates and caches the geographic tile boundaries only when requested.
          def bounds
            @bounds ||= GeoTileBounds.new(schema, latitude(y), latitude(y + 1), longitude(x + 1), longitude(x))
          end

          # Wraps the bounds as individually selectable geographic corners.
          def corners
            GeoTileCorners.new(schema, bounds)
          end

          private

          # Converts a horizontal tile coordinate to longitude in degrees.
          def longitude(tile_x)
            tile_x / tile_count_per_axis * 360.0 - 180.0
          end

          # Converts a vertical tile coordinate using inverse Web Mercator projection.
          def latitude(tile_y)
            Math.atan(Math.sinh(Math::PI * (1.0 - 2.0 * tile_y / tile_count_per_axis))) * 180.0 / Math::PI
          end

          # Returns the number of tiles along either axis at this zoom level.
          def tile_count_per_axis
            2.0**zoom_level
          end
        end

        # Resolves individually selected latitude and longitude boundaries.
        class GeoTileBounds < GraphQL::Resolvers::ResolvableValue.new(:north, :south, :east, :west)
        end

        # Resolves individual corners from their shared geographic bounds.
        class GeoTileCorners < GraphQL::Resolvers::ResolvableValue.new(:bounds)
          # Resolves the northwest corner using GeoLocation's indexed field names.
          def northwest
            {"lat" => bounds.north, "lon" => bounds.west}
          end

          # Resolves the northeast corner using GeoLocation's indexed field names.
          def northeast
            {"lat" => bounds.north, "lon" => bounds.east}
          end

          # Resolves the southwest corner using GeoLocation's indexed field names.
          def southwest
            {"lat" => bounds.south, "lon" => bounds.west}
          end

          # Resolves the southeast corner using GeoLocation's indexed field names.
          def southeast
            {"lat" => bounds.south, "lon" => bounds.east}
          end
        end
      end
    end
  end
end
