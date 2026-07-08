# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/errors"
require "elastic_graph/proto_ingestion/schema_definition/identifier"
require "elastic_graph/proto_ingestion/schema_definition/schema_elements/proto_documentation"
require "elastic_graph/support/casing"

module ElasticGraph
  module ProtoIngestion
    module SchemaDefinition
      # Protobuf schema definition extensions for ElasticGraph schema elements.
      module SchemaElements
        # Extends EnumType with proto field type conversion.
        module EnumTypeExtension
          # Defines an enum value and immediately validates its protobuf name.
          #
          # @return [void]
          def value(value_name, &block)
            super
            new_value = values_by_name.values.last # : ::ElasticGraph::SchemaDefinition::SchemaElements::EnumValue & EnumValueExtension
            new_proto_name = new_value.proto_name(enum_value_prefix)
            zero_value_name = "#{enum_value_prefix}_UNSPECIFIED"

            if new_proto_name == zero_value_name
              raise Errors::SchemaError, "Enum `#{name}` value `#{new_value.name}` maps to proto enum value name " \
                "`#{new_proto_name}`, which conflicts with the generated zero value `#{zero_value_name}`."
            end

            duplicate = values_by_name.values.find do |raw_value|
              existing_value = raw_value # : ::ElasticGraph::SchemaDefinition::SchemaElements::EnumValue & EnumValueExtension
              !existing_value.equal?(new_value) && existing_value.proto_name(enum_value_prefix) == new_proto_name
            end

            if duplicate
              raise Errors::SchemaError, "Enum `#{name}` values `#{duplicate.name}` and `#{new_value.name}` " \
                "map to duplicate proto enum value name `#{new_proto_name}`."
            end

            nil
          end

          # Renders this enum's protobuf definition.
          #
          # @return [String]
          def to_proto(schema)
            render_proto_enum(schema)
          end

          # Returns the kind used to order this definition in a protobuf schema.
          #
          # @return [Symbol]
          def proto_definition_kind
            :enum
          end

          # Returns the schema types referenced by this definition.
          #
          # @return [Array]
          def referenced_proto_types
            []
          end

          # Returns this enum type's name in protobuf schemas.
          #
          # @return [String]
          def proto_name
            @proto_name ||= Identifier.enum_name(name)
          end

          # @private
          def configure_derived_scalar_type(scalar_type)
            super
            proto_scalar_type = scalar_type # : ::ElasticGraph::SchemaDefinition::SchemaElements::ScalarType & ScalarTypeExtension
            proto_scalar_type.protobuf type: proto_name
          end

          private

          def render_proto_enum(schema)
            values = values_by_name.values
            value_numbers = schema.enum_value_numbers_for(proto_name, values_by_name.keys)

            zero_value_name = "#{enum_value_prefix}_UNSPECIFIED"

            lines = ProtoDocumentation.comment_lines_for(doc_comment)
            lines << "enum #{proto_name} {"
            lines << "  // The default value when no enum value has been explicitly set. Do not use this value."
            lines << "  // See https://protobuf.dev/programming-guides/proto3/#enum-default."
            lines << "  #{zero_value_name} = 0;"
            values.each do |raw_value|
              value = raw_value # : ::ElasticGraph::SchemaDefinition::SchemaElements::EnumValue & EnumValueExtension
              lines.concat(ProtoDocumentation.comment_lines_for(value.doc_comment, indent: "  "))
              lines << "  #{value.proto_name(enum_value_prefix)} = #{value_numbers.fetch(value.name)};"
            end
            lines << "}"
            lines.join("\n")
          end

          def enum_value_prefix
            Support::Casing.to_upper_snake(name)
          end
        end
      end
    end
  end
end
