# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  class GraphQL
    module Resolvers
      # Defines the resolver interface, which our extension loader will validate against.
      class Interface
        def initialize(elasticgraph_graphql:, config:)
          # must be defined, but nothing to do
        end

        def resolve(field:, object:, args:, context:, lookahead:)
        end
      end
    end
  end
end
