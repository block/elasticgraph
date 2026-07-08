# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/errors"
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
          def value(value_name)
            super(value_name) do |new_value|
              new_proto_name = new_value.proto_name(proto_enum_value_prefix)

              if new_proto_name == proto_zero_value_name
                raise Errors::SchemaError, "Enum `#{name}` value `#{new_value.name}` maps to proto enum value name " \
                  "`#{new_proto_name}`, which conflicts with the generated zero value `#{proto_zero_value_name}`."
              end

              if (duplicate = values_by_proto_name[new_proto_name])
                raise Errors::SchemaError, "Enum `#{name}` values `#{duplicate.name}` and `#{new_value.name}` " \
                  "map to duplicate proto enum value name `#{new_proto_name}`."
              end

              yield new_value if block_given?
              values_by_proto_name[new_proto_name] = new_value
            end
          end

          # Renders this enum's protobuf definition.
          #
          # @return [String]
          def to_proto(schema, _package_name)
            render_proto_enum(schema)
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
            name
          end

          # Returns the fully qualified name used to reference this enum from protobuf fields.
          #
          # @return [String]
          def proto_type_reference(package_name)
            ".#{package_name}.#{proto_name}"
          end

          # @private
          def configure_derived_scalar_type(scalar_type)
            super
            proto_scalar_type = scalar_type # : ::ElasticGraph::SchemaDefinition::SchemaElements::ScalarType & ScalarTypeExtension
            proto_scalar_type.protobuf type: proto_name
          end

          private

          def render_proto_enum(schema)
            documentation = ProtoDocumentation.comment_lines_for(doc_comment).map { |line| "#{line}\n" }.join
            values = values_by_name.values
            value_numbers = schema.enum_value_numbers_for(proto_name, values_by_name.keys)
            value_definitions = [proto_zero_value.to_proto(0, proto_enum_value_prefix: proto_enum_value_prefix)]
            value_definitions.concat(values.map do |raw_value|
              value = raw_value # : ::ElasticGraph::SchemaDefinition::SchemaElements::EnumValue & EnumValueExtension
              value.to_proto(value_numbers.fetch(value.name), proto_enum_value_prefix: proto_enum_value_prefix)
            end)

            <<~PROTO.chomp
              #{documentation}enum #{proto_name} {
              #{value_definitions.join("\n")}
              }
            PROTO
          end

          def proto_zero_value
            @proto_zero_value ||= begin
              factory = schema_def_state.factory # : ::ElasticGraph::SchemaDefinition::Factory & ::ElasticGraph::ProtoIngestion::SchemaDefinition::FactoryExtension
              factory.new_enum_value("UNSPECIFIED", "UNSPECIFIED") do |value|
                value.documentation <<~EOS
                  The default value when no enum value has been explicitly set. Do not use this value.
                  See https://protobuf.dev/programming-guides/proto3/#enum-default.
                EOS
              end
            end
          end

          def proto_zero_value_name
            @proto_zero_value_name ||= "#{proto_enum_value_prefix}_UNSPECIFIED"
          end

          def proto_enum_value_prefix
            @proto_enum_value_prefix ||= Support::Casing.to_upper_snake(name)
          end

          def values_by_proto_name
            @values_by_proto_name ||= {}
          end
        end
      end
    end
  end
end
