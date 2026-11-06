# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphql/aggregation/resolvers/geo_tile"

module ElasticGraph
  class GraphQL
    module Aggregation
      module Resolvers
        # Selects geographic tile resolution through schema metadata rather than a generic resolver type check.
        class AsGeoTile
          # Satisfies the resolver interface; this resolver needs no instance configuration.
          def initialize(elasticgraph_graphql:, config:)
          end

          # Wraps the raw bucket key, preserving null for documents with no location.
          def resolve(field:, object:, args:, context:, lookahead:)
            object.key_value_for(field: field, lookahead: lookahead)&.then do |key|
              GeoTile.from_key(context.elastic_graph_schema, key)
            end
          end
        end
      end
    end
  end
end
