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
      # Resolver which just delegates to `object` for resolving.
      class Object
        def initialize(elasticgraph_graphql:, config:)
          # Nothing to initialize, but needs to be defined to satisfy the resolver interface.
        end

        def resolve(field:, object:, args:, context:, lookahead:)
          object.resolve(field: field, object: object, args: args, context: context, lookahead: lookahead)
        end
      end
    end
  end
end
