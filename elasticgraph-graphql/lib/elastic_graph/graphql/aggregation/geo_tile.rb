# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  class GraphQL
    module Aggregation
      # Decodes datastore tile keys into the geographic representations exposed by GraphQL.
      # The inverse formulas follow [Elasticsearch's GeoTileUtils](https://github.com/elastic/elasticsearch/blob/36a8b81764d3448666ad213c3b47762e5fa22d42/server/src/main/java/org/elasticsearch/search/aggregations/bucket/geogrid/GeoTileUtils.java)
      # (`toBoundingBox` and `zxyToGeoPoint`).
      # [OpenSearch's GeoTileUtils](https://github.com/opensearch-project/OpenSearch/blob/d016718b1718659f39d1e587a33fad5dc54fd711/server/src/main/java/org/opensearch/search/aggregations/bucket/GeoTileUtils.java)
      # uses the same formulas.
      #
      # Below zoom level 20, our values match apart from small differences caused by the datastores'
      # approximate sinh/atan functions. At zoom level 20 and above, Elasticsearch snaps latitude bounds
      # to Lucene's coordinate grid. We retain the unsnapped values; the difference is less than 1 cm.
      #
      # Uses [Web Mercator XYZ coordinates](https://wiki.openstreetmap.org/wiki/Slippy_map_tilenames).
      module GeoTile
        # Converts a datastore XYZ tile key into the configured GraphQL tile representation.
        def self.decode(key, names:)
          coordinates = key.split("/").map(&:to_i)
          zoom = coordinates.fetch(0)
          x = coordinates.fetch(1)
          y = coordinates.fetch(2)
          n = 2.0**zoom
          west = longitude(x, n)
          east = longitude(x + 1, n)
          north = latitude(y, n)
          south = latitude(y + 1, n)

          # GeoLocation uses lat/lon in its index mapping, regardless of GraphQL field casing or overrides.
          {
            names.zoom_level => zoom,
            names.x => x,
            names.y => y,
            names.center_point => {"lat" => latitude(y + 0.5, n), "lon" => longitude(x + 0.5, n)},
            names.bounds => {names.north => north, names.south => south, names.east => east, names.west => west},
            names.corners => {
              names.north_west => {"lat" => north, "lon" => west},
              names.north_east => {"lat" => north, "lon" => east},
              names.south_west => {"lat" => south, "lon" => west},
              names.south_east => {"lat" => south, "lon" => east}
            }
          }
        end

        # Converts a horizontal tile coordinate to longitude in degrees.
        def self.longitude(x, n)
          x / n * 360.0 - 180.0
        end
        private_class_method :longitude

        # Converts a vertical tile coordinate to latitude using inverse Web Mercator projection.
        def self.latitude(y, n)
          Math.atan(Math.sinh(Math::PI * (1.0 - 2.0 * y / n))) * 180.0 / Math::PI
        end
        private_class_method :latitude
      end
    end
  end
end
