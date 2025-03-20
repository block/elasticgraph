# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphql/resolvers/relay_connection/page_info"
require "elastic_graph/graphql/resolvers/resolvable_value"

module ElasticGraph
  class GraphQL
    module Resolvers
      module RelayConnection
        class GenericAdapter < ResolvableValue.new(
          # Array of nodes for this page of data, before paginator truncation has been added.
          :raw_nodes,
          # The paginator that's being used.
          :paginator,
          # Lambda that is used to convert a node to a sort value during truncation.
          :to_sort_value,
          # Gets an optional count of total edges.
          :get_total_edge_count
        )
          # @dynamic initialize, with, schema_element_names, raw_nodes, paginator, to_sort_value, get_total_edge_count

          def page_info
            @page_info ||= PageInfo.new(
              schema_element_names: schema_element_names,
              before_truncation_nodes: before_truncation_nodes,
              edges: edges,
              paginator: paginator
            )
          end

          def total_edge_count
            get_total_edge_count.call
          end

          def edges
            @edges ||= nodes.map { |node| Edge.new(schema_element_names, node) }
          end

          def nodes
            @nodes ||= paginator.truncate_items(before_truncation_nodes, &to_sort_value)
          end

          private

          def before_truncation_nodes
            @before_truncation_nodes ||= paginator.restore_intended_item_order(raw_nodes)
          end

          # Implements an `Edge` as per the relay spec:
          # https://facebook.github.io/relay/graphql/connections.htm#sec-Edge-Types
          class Edge < ResolvableValue.new(:node)
            # @dynamic initialize, node
            def cursor = node.cursor.encode
          end
        end
      end
    end
  end
end
