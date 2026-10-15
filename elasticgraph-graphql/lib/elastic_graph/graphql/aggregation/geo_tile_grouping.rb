# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/constants"
require "elastic_graph/graphql/aggregation/field_path_encoder"
require "elastic_graph/support/memoizable_data"
require "graphql"

module ElasticGraph
  class GraphQL
    module Aggregation
      # Groups a geo_point field into Web Mercator XYZ tiles.
      class GeoTileGrouping < Support::MemoizableData.define(:field_path, :zoom_level)
        # Identifies the grouping in response buckets using the client's field names and aliases.
        def key
          @key ||= FieldPathEncoder.encode(field_path.map(&:name_in_graphql_query))
        end

        # Returns the indexed field path, excluding GraphQL-only grouping operations.
        def encoded_index_field_path
          @encoded_index_field_path ||= FieldPathEncoder.join(field_path.filter_map(&:name_in_index))
        end

        # Builds a geo-tile aggregation clause, translating the zoom level to datastore precision.
        def composite_clause(grouping_options: {})
          {"geotile_grid" => {"field" => encoded_index_field_path, "precision" => zoom_level}.merge(grouping_options)}
        end

        # Builds a standalone geo-tile clause limited to the requested number of buckets.
        def non_composite_clause_for(query)
          composite_clause(grouping_options: {"size" => query.paginator.requested_page_size})
        end

        # Composite geo tiles are sorted by their packed numeric XYZ coordinates, not lexicographically
        # by their string keys (for example, column 40 precedes column 215).
        def sort_value(tile_key)
          return nil if tile_key.nil?
          unless tile_key.is_a?(::String) && /\A\d{1,2}\/\d{1,9}\/\d{1,9}\z/.match?(tile_key)
            raise ::GraphQL::ExecutionError, "Invalid geo tile cursor value for `#{key}`."
          end

          zoom, x, y = tile_key.split("/").map { |part| Integer(part, 10) } # : [::Integer, ::Integer, ::Integer]
          unless zoom == zoom_level && x < (1 << zoom_level) && y < (1 << zoom_level)
            raise ::GraphQL::ExecutionError, "Invalid geo tile cursor value for `#{key}`."
          end
          coordinate_bits = GEO_TILE_ZOOM_LEVELS.max # : ::Integer
          (zoom << (2 * coordinate_bits)) | (x << coordinate_bits) | y
        end

        # Requests a separate missing-value aggregation because standalone geo grids omit missing locations.
        def handles_missing_values?
          false
        end

        # Geo grid buckets report no count error, so a `value_count` aggregation provides the data to bound it.
        def bounds_count_error_with_value_count?
          true
        end

        def inner_meta
          INNER_META
        end

        INNER_META = {"key_path" => ["key"], "merge_into_bucket" => {}}
      end
    end
  end
end
