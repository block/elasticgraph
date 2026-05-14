# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  class GraphQL
    module Resolvers
      # Resolves fields whose return type is a {SchemaDefinition::API#namespace_type namespace type}. A
      # namespace type is a pure GraphQL grouping construct with no backing data, so the resolver returns
      # an empty hash as a non-null passthrough object; each child field has its own resolver that does
      # not read from the parent.
      #
      # This is auto-wired by the schema definition layer on any no-argument field whose return type is a
      # namespace type. Users do not typically reference this resolver directly.
      class NamespaceRef
        def initialize(elasticgraph_graphql:, config:)
        end

        def resolve(field:, object:, args:, context:)
          {}
        end
      end
    end
  end
end
