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
          # Describes an external proto enum registered as the source of this enum's generated values.
          ExternalProtoEnumSource = ::Data.define(:proto_enum, :exclusions, :expected_extras, :name_transform)

          # Sources this enum's generated proto values from an existing proto enum class.
          #
          # @return [void]
          def external_proto_enum(proto_enum, exclusions: [], expected_extras: [], name_transform: nil)
            unless proto_enum.respond_to?(:enums)
              raise Errors::SchemaError, "`external_proto_enum` on `#{name}` must be given a proto enum class with `.enums`, " \
                "but got: #{proto_enum.inspect}."
            end

            external_proto_enum_sources << ExternalProtoEnumSource.new(
              proto_enum: proto_enum,
              exclusions: exclusions.map(&:to_s),
              expected_extras: expected_extras.map(&:to_s),
              name_transform: name_transform
            )
            nil
          end

          # External proto enums registered via {#external_proto_enum}.
          #
          # @return [Array<ExternalProtoEnumSource>]
          def external_proto_enum_sources
            @external_proto_enum_sources ||= []
          end

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
            source_value_names = proto_enum_value_names
            proto_value_names_by_source_name = source_value_names.to_h do |source_name|
              [source_name, proto_enum_value_name(source_name)]
            end
            duplicate_names = proto_value_names_by_source_name.values.tally.select { |_, count| count > 1 }
            if duplicate_names.any?
              raise Errors::SchemaError, "Enum `#{name}` maps to duplicate proto enum value names: #{duplicate_names.keys.sort.join(", ")}."
            end
            value_numbers = schema.enum_value_numbers_for(proto_name, source_value_names)

            zero_value_name = "#{enum_value_prefix}_UNSPECIFIED"
            if (source_name = proto_value_names_by_source_name.key(zero_value_name))
              raise Errors::SchemaError, "Enum `#{name}` value `#{source_name}` maps to proto enum value name " \
                "`#{zero_value_name}`, which conflicts with the generated zero value `#{zero_value_name}`."
            end

            lines = ProtoDocumentation.comment_lines_for(doc_comment)
            lines << "enum #{proto_name} {"
            lines << "  // The default value when no enum value has been explicitly set. Do not use this value."
            lines << "  // See https://protobuf.dev/programming-guides/proto3/#enum-default."
            lines << "  #{zero_value_name} = 0;"
            proto_value_names_by_source_name.each do |source_name, proto_value_name|
              if (raw_value = values_by_name[source_name])
                value = raw_value # : ::ElasticGraph::SchemaDefinition::SchemaElements::EnumValue & EnumValueExtension
                lines.concat(ProtoDocumentation.comment_lines_for(value.doc_comment, indent: "  "))
              end
              lines << "  #{proto_value_name} = #{value_numbers.fetch(source_name)};"
            end
            lines << "}"
            lines.join("\n")
          end

          def enum_value_prefix
            Support::Casing.to_upper_snake(name)
          end

          def proto_enum_value_name(value_name)
            if (raw_value = values_by_name[value_name])
              value = raw_value # : ::ElasticGraph::SchemaDefinition::SchemaElements::EnumValue & EnumValueExtension
              value.proto_name(enum_value_prefix)
            else
              Identifier.enum_value_name("#{enum_value_prefix}_#{Support::Casing.to_upper_snake(value_name)}")
            end
          end

          def proto_enum_value_names
            return values_by_name.keys if external_proto_enum_sources.empty?

            values_by_source = external_proto_enum_sources.map { |source| enum_value_names_from_source(source) }
            canonical_values = values_by_source.first
            canonical_set = canonical_values.uniq.sort
            if values_by_source.drop(1).any? { |source_values| source_values.uniq.sort != canonical_set }
              raise Errors::SchemaError, "External proto enums for `#{name}` produce inconsistent value sets. " \
                "Ensure each `external_proto_enum` source (with exclusions/expected_extras/name_transform) resolves to the same values."
            end
            canonical_values
          end

          def enum_value_names_from_source(source)
            name_transform = source.name_transform || :itself.to_proc
            mapped_values = source.proto_enum.enums.map { |enum_entry| name_transform.call(enum_entry.name.to_s).to_s }
            (mapped_values - source.exclusions + source.expected_extras).uniq
          rescue => e
            raise Errors::SchemaError, "Failed loading external proto enum values for `#{name}` from `#{source.proto_enum}`: #{e.message}"
          end
        end
      end
    end
  end
end
