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
require "forwardable"

module ElasticGraph
  module ProtoIngestion
    module SchemaDefinition
      # Builds a `proto2` or `proto3` schema string from an ElasticGraph schema definition.
      class Schema
        extend Forwardable

        # Protobuf syntaxes this generator can emit.
        SUPPORTED_SYNTAXES = %w[proto2 proto3].freeze

        # The protobuf syntax emitted when the schema does not configure one.
        DEFAULT_SYNTAX = "proto3"

        # Normalizes a configured `syntax` to one of {SUPPORTED_SYNTAXES}.
        #
        # Both the `proto_schema_artifacts` API and this class validate through here so that a
        # syntax is checked exactly once no matter which entry point supplies it.
        #
        # @param syntax [Symbol, String]
        # @return [String]
        def self.validate_syntax(syntax)
          syntax.to_s.tap do |normalized|
            unless SUPPORTED_SYNTAXES.include?(normalized)
              raise Errors::SchemaError, "`syntax` must be one of #{SUPPORTED_SYNTAXES.inspect}, got: #{syntax.inspect}"
            end
          end
        end

        # Validates configured `header_lines`, as {.validate_syntax} does for a syntax.
        #
        # Each element renders as its own line, so a newline in one element would silently produce
        # more lines than the schema asked for.
        #
        # @param header_lines [Array<String>]
        # @return [Array<String>]
        def self.validate_header_lines(header_lines)
          unless header_lines.is_a?(::Array) && header_lines.all?(::String)
            raise Errors::SchemaError, "`header_lines` must be an Array of Strings, got: #{header_lines.inspect}"
          end

          if (multi_line = header_lines.grep(/\n/)).any?
            raise Errors::SchemaError, "`header_lines` must not contain newlines, but got: #{multi_line.inspect}. " \
              "Pass one Array element per line."
          end

          header_lines
        end

        # @param state [ElasticGraph::SchemaDefinition::State]
        # @param all_types [Array<ElasticGraph::SchemaDefinition::SchemaElements::graphQLType>]
        # @param ingestion_state [ProtoIngestionState] this extension's configured schema definition state
        def initialize(state:, all_types:, ingestion_state:)
          @state = state
          @all_types = all_types
          @package_name = ingestion_state.package_name
          @syntax = self.class.validate_syntax(ingestion_state.syntax)
          @header_lines = self.class.validate_header_lines(ingestion_state.header_lines)
          @field_number_mappings = FieldNumberMappings.from_parsed_yaml(ingestion_state.field_number_mappings)
        end

        # Renders the schema as a valid file in the configured syntax.
        #
        # @return [String]
        def to_proto
          types = proto_types
          return "" if types.empty?

          validate_unique_enum_value_prefixes(types)

          sections = [
            %(syntax = "#{@syntax}";),
            "package #{@package_name};",
            *render_header_lines,
            *render_imports(types),
            render_definitions(types)
          ]

          sections.join("\n\n") + "\n"
        end

        # Exposes the field-number and enum-value-number mappings for writing to artifact YAML.
        #
        # @return [Hash<String, Object>]
        def field_number_mappings_for_artifact
          @field_number_mappings.to_dumpable_hash
        end

        # Returns the stable protobuf number for a message field.
        #
        # @api private
        def field_number_for(message_name:, type_name:, public_field_name:)
          @field_number_mappings.field_number_for(
            message_name: message_name,
            public_field_name: public_field_name,
            previous_field_names: previous_field_names_for(type_name, public_field_name)
          )
        end

        # @dynamic next_field_number_for, reserved_field_numbers_for, enum_value_numbers_for
        # @dynamic next_enum_value_number_for, reserved_enum_value_numbers_for, pinned_enum_value_numbers
        # @dynamic pin_enum_value_numbers
        def_delegators :@field_number_mappings,
          :next_field_number_for,
          :reserved_field_numbers_for,
          :enum_value_numbers_for,
          :next_enum_value_number_for,
          :reserved_enum_value_numbers_for,
          :pinned_enum_value_numbers,
          :pin_enum_value_numbers

        # Returns the label prefix (including its trailing space) that a field declaration needs
        # under the configured syntax, or an empty string when the field takes no label.
        #
        # `proto2` requires an explicit label on every field, so non-repeated fields get
        # `optional `; `proto3` labels repeated fields only. Note that `oneof` alternatives never
        # get a label under either syntax -- protoc rejects one -- so the `oneof` renderer in
        # `ObjectInterfaceAndUnionExtension` does not call this.
        #
        # @api private
        def field_label_prefix(repeated:)
          return "repeated " if repeated
          proto2? ? "optional " : ""
        end

        # Indicates whether the generator emits `proto2` rather than `proto3`.
        #
        # @api private
        def proto2?
          @syntax == "proto2"
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

        # Every type reports the proto file it needs imported, or `nil` when it needs none. Today only
        # scalar types map to an externally defined proto type, but enum and object types can start
        # requiring an import without any change here.
        def render_imports(types)
          imports = types.filter_map(&:protobuf_import).uniq.sort

          imports.empty? ? [] : [imports.map { |import| %(import "#{import}";) }.join("\n")]
        end

        def render_header_lines
          @header_lines.empty? ? [] : [@header_lines.join("\n")]
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
          previous_field_names_by_type_name_and_field_name.dig(type_name, public_field_name) || []
        end

        # Inverts the state's `old_field_name => renamed_field` index into the form we need here:
        # the old public names a field's current public name was renamed from.
        def previous_field_names_by_type_name_and_field_name
          @previous_field_names_by_type_name_and_field_name ||= @state.renamed_fields_by_type_name_and_old_field_name.transform_values do |old_to_new|
            old_to_new
              .group_by { |_, renamed_field| renamed_field.name }
              .transform_values { |renames| renames.map(&:first) }
          end
        end
      end
    end
  end
end
