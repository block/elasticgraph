# Copyright 2024 - 2025 Block, Inc.
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
        class ArrayAdapter < ResolvableValue.new(:graphql_impl)
          # `ResolvableValue.new` provides the following methods:
          # @dynamic initialize, graphql_impl, schema_element_names

          # `def_delegators` provides the following methods:
          # @dynamic start_cursor, end_cursor, has_next_page, has_previous_page
          extend Forwardable
          def_delegators :graphql_impl, :start_cursor, :end_cursor, :has_next_page, :has_previous_page

          def self.build(nodes, args, schema_element_names, context)
            # ElasticGraph supports any schema elements (like a `first` argument) being renamed,
            # but `GraphQL::Relay::ArrayConnection` would not understand a renamed argument.
            # Here we map the args back to the canonical relay args so `ArrayConnection` can
            # understand them.
            relay_args = [:first, :after, :last, :before].to_h do |arg_name|
              [arg_name, args[schema_element_names.public_send(arg_name)]]
            end.compact

            graphql_impl = ::GraphQL::Pagination::ArrayConnection.new(nodes || [], context: context, **relay_args)
            new(schema_element_names, graphql_impl)
          end

          def total_edge_count
            graphql_impl.nodes.size
          end

          def page_info
            self
          end

          def edges
            @edges ||= graphql_impl.nodes.map do |node|
              Edge.new(schema_element_names, graphql_impl, node)
            end
          end

          def nodes
            @nodes ||= graphql_impl.nodes
          end

          # Simple edge implementation for a node object.
          class Edge < ResolvableValue.new(:graphql_impl, :node)
            # `ResolvableValue.new` provides the following methods:
            # @dynamic initialize, graphql_impl, schema_element_names, node

            def cursor
              graphql_impl.cursor_for(node)
            end
          end
        end
      end
    end
  end
end
