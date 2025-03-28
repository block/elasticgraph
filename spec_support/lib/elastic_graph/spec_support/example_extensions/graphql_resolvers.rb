# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  class GraphQLResolverWithLookahead
    def initialize(elasticgraph_graphql:, config:)
    end

    def resolve(field:, object:, args:, context:, lookahead:)
    end
  end

  class GraphQLResolverWithoutLookahead
    def initialize(elasticgraph_graphql:, config:)
    end

    def resolve(field:, object:, args:, context:)
    end
  end

  class MissingArgumentsResolver
    def initialize(elasticgraph_graphql:, config:)
    end

    def resolve(field:, object:, args:)
    end
  end
end
