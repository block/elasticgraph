# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphql/resolvers/resolvable_value"
require "forwardable"

module ElasticGraph
  class GraphQL
    module Resolvers
      module RelayConnection
        # Relay connection adapter for an array. Implemented primarily by `GraphQL::Relay::ArrayConnection`;
        # here we just adapt it to the ElasticGraph internal resolver interface.
        class ArrayAdapter < ResolvableValue.new(:graphql_impl, :total_edge_count)
          # `ResolvableValue.new` provides the following methods:
          # @dynamic initialize, graphql_impl, total_edge_count, schema

          # `def_delegators` provides the following methods:
          # @dynamic start_cursor, end_cursor, has_next_page, has_previous_page
          extend Forwardable

          def_delegators :graphql_impl, :start_cursor, :end_cursor, :has_next_page, :has_previous_page

          def self.build(nodes, args, context)
            schema = context.fetch(:elastic_graph_schema)
            schema_element_names = schema.element_names
            nodes ||= [] # : ::Array[untyped]

            # ElasticGraph supports any schema elements (like a `first` argument) being renamed,
            # but `GraphQL::Relay::ArrayConnection` would not understand a renamed argument.
            # Here we map the args back to the canonical relay args so `ArrayConnection` can
            # understand them.
            #
            # `after` and `before` are encoded to convert them to the string form required by `ArrayConnection`.
            relay_args = {
              first: args[schema_element_names.first],
              after: args[schema_element_names.after]&.encode,
              last: args[schema_element_names.last],
              before: args[schema_element_names.before]&.encode
            }.compact

            graphql_impl = ::GraphQL::Pagination::ArrayConnection.new(nodes, context: context, **relay_args)
            new(schema, graphql_impl, nodes.size)
          end

          def page_info
            self
          end

          def edges
            @edges ||= graphql_impl.nodes.map do |node|
              Edge.new(schema, graphql_impl, node)
            end
          end

          def nodes
            @nodes ||= graphql_impl.nodes
          end

          # Simple edge implementation for a node object.
          class Edge < ResolvableValue.new(:graphql_impl, :node)
            # `ResolvableValue.new` provides the following methods:
            # @dynamic initialize, graphql_impl, schema, node

            def cursor
              graphql_impl.cursor_for(node)
            end
          end
        end
      end
    end
  end
end
