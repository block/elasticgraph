# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  class GraphQL
    module Aggregation
      PathSegment = ::Data.define(
        # The name of this segment's field in the GraphQL query. If it's an aliased field, this
        # will be the alias name.
        :name_in_graphql_query,
        # The name of this segment's field in the datastore index.
        :name_in_index
      ) do
        # Factory method that aids in building a `PathSegment` for a given `field` and `lookahead` node.
        def self.for(lookahead:, field: nil)
          ast_node = lookahead.ast_nodes.first # : ::GraphQL::Language::Nodes::Field

          new(
            name_in_graphql_query: ast_node.alias || ast_node.name,
            name_in_index: field&.name_in_index
          )
        end
      end
    end
  end
end
