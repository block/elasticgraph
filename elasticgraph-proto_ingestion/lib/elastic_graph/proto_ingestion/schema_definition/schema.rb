# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/errors"
require "elastic_graph/proto_ingestion/schema_definition/field_number_mappings"
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
        # @param proto_field_number_mappings [Hash, nil] mappings in the `proto_field_numbers.yaml` artifact format
        def initialize(
          state:,
          all_types:,
          package_name:,
          proto_field_number_mappings: {}
        )
          @state = state
          @all_types = all_types
          @package_name = package_name
          @field_number_mappings = FieldNumberMappings.from_artifact(proto_field_number_mappings)
        end

        # Renders the schema as a valid `proto3` file.
        #
        # @return [String]
        def to_proto
          types = proto_types
          return "" if types.empty?

          validate_unique_enum_value_prefixes(types)

          sections = [
            %(syntax = "proto3";),
            "package #{@package_name};",
            render_definitions(types)
          ]

          sections.join("\n\n") + "\n"
        end

        # Exposes the field-number and enum-value-number mappings for writing to artifact YAML.
        #
        # @return [Hash<String, Object>]
        def field_number_mappings_for_artifact
          @field_number_mappings.to_artifact
        end

        # Returns the stable protobuf number for a message field.
        #
        # @api private
        def field_number_for(message_name:, type_name:, public_field_name:, name_in_index:)
          @field_number_mappings.field_number_for(
            message_name: message_name,
            public_field_name: public_field_name,
            name_in_index: name_in_index,
            previous_field_names: previous_field_names_for(type_name, public_field_name)
          )
        end

        # Returns the stable protobuf numbers for an enum's values.
        #
        # @api private
        def enum_value_numbers_for(enum_name, value_names)
          @field_number_mappings.enum_value_numbers_for(enum_name, value_names)
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
            type_names_to_render.include?(type.name)
          end
        end

        def render_definitions(types)
          types
            .sort_by(&:proto_name)
            .filter_map { |type| type.to_proto(self, @package_name) }
            .join("\n\n")
        end

        def validate_unique_enum_value_prefixes(types)
          enum_type_by_prefix = {} # : ::Hash[::String, untyped]

          types.grep(SchemaElements::EnumTypeExtension).each do |type|
            if (existing_enum_type = enum_type_by_prefix[type.proto_enum_value_prefix])
              raise Errors::SchemaError, "Enum types `#{existing_enum_type.name}` and `#{type.name}` map to " \
                "duplicate protobuf enum value prefix `#{type.proto_enum_value_prefix}`."
            end

            enum_type_by_prefix[type.proto_enum_value_prefix] = type
          end
        end

        def previous_field_names_for(type_name, public_field_name)
          renamed_public_field_names_by_type_name.dig(type_name, public_field_name) || []
        end

        def renamed_public_field_names_by_type_name
          @renamed_public_field_names_by_type_name ||= @state.renamed_fields_by_type_name_and_old_field_name.transform_values do |old_to_new|
            old_to_new
              .group_by { |_, renamed_field| renamed_field.name }
              .transform_values { |renames| renames.map(&:first) }
          end
        end
      end
    end
  end
end
