# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/proto_ingestion/schema_definition/identifier"
require "elastic_graph/proto_ingestion/schema_definition/schema_elements/enum_type_extension"
require "elastic_graph/proto_ingestion/schema_definition/schema_elements/object_interface_and_union_extension"
require "elastic_graph/proto_ingestion/schema_definition/schema_elements/scalar_type_extension"

module ElasticGraph
  module ProtoIngestion
    module SchemaDefinition
      # Builds a `proto3` schema string from an ElasticGraph schema definition.
      class Schema
        # @param state [ElasticGraph::SchemaDefinition::State]
        # @param all_types [Array<ElasticGraph::SchemaDefinition::SchemaElements::graphQLType>]
        # @param package_name [String]
        def initialize(state:, all_types:, package_name:)
          @state = state
          @all_types = all_types
          @package_name = Identifier.validate_package_name(package_name)
        end

        # Renders the schema as a valid `proto3` file.
        #
        # @return [String]
        def to_proto
          types = proto_types
          return "" if types.empty?

          sections = [
            %(syntax = "proto3";),
            "package #{@package_name};",
            render_definitions(types)
          ]

          sections.join("\n\n") + "\n"
        end

        private

        # Selects the indexed root types and every type transitively referenced by their protobuf
        # representations. All traversal state is local so repeated calls are independent.
        def proto_types
          types_to_visit = _ = @state.indexed_types_by_index_name.values.dup
          type_names_to_render = ::Set.new

          while (type = types_to_visit.shift)
            next unless type_names_to_render.add?(type.name)

            types_to_visit.concat(type.referenced_proto_types)
          end

          @all_types.select do |type|
            type_names_to_render.include?(type.name) && type.respond_to?(:to_proto)
          end
        end

        def render_definitions(types)
          types
            .sort_by { |type| [(type.proto_definition_kind == :enum) ? 0 : 1, type.proto_name] }
            .filter_map(&:to_proto)
            .join("\n\n")
        end
      end
    end
  end
end
