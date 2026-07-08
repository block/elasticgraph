# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/errors"
require "elastic_graph/proto_ingestion/schema_definition/identifier"
require "elastic_graph/proto_ingestion/schema_definition/schema_elements/enum_type_extension"
require "elastic_graph/proto_ingestion/schema_definition/schema_elements/object_interface_and_union_extension"
require "elastic_graph/proto_ingestion/schema_definition/schema_elements/scalar_type_extension"

module ElasticGraph
  module ProtoIngestion
    module SchemaDefinition
      # Builds a `proto2` or `proto3` schema string from an ElasticGraph schema definition.
      class Schema
        # Internal representation of a stored field-number mapping.
        #
        # @!attribute [r] field_number
        #   @return [Integer]
        # @!attribute [r] name_in_index
        #   @return [String]
        FieldNumberMapping = ::Data.define(:field_number, :name_in_index)

        # The largest field number protobuf allows (2^29 - 1).
        MAX_FIELD_NUMBER = 536_870_911
        # Field numbers protobuf reserves for its own implementation; they may not be used as field tags.
        RESERVED_FIELD_NUMBER_RANGE = 19_000..19_999
        # The largest enum value number protobuf allows (the int32 maximum).
        MAX_ENUM_VALUE_NUMBER = 2_147_483_647
        # Protobuf syntaxes this generator can emit.
        SUPPORTED_SYNTAXES = %w[proto2 proto3].freeze

        # @param state [ElasticGraph::SchemaDefinition::State]
        # @param all_types [Array<ElasticGraph::SchemaDefinition::SchemaElements::graphQLType>]
        # @param package_name [String]
        # @param proto_field_number_mappings [Hash]
        def initialize(
          state:,
          all_types:,
          package_name:,
          proto_field_number_mappings: {},
          syntax: :proto3,
          headers: []
        )
          @syntax = syntax.to_s
          @headers = headers
          @state = state
          @all_types = all_types
          @package_name = Identifier.validate_package_name(package_name)
          @proto_field_number_mappings_by_message = normalize_proto_field_number_mappings(proto_field_number_mappings)
          @proto_enum_value_numbers_by_enum = normalize_proto_enum_value_number_mappings(proto_field_number_mappings)
          @used_field_numbers_by_message = {}
          @used_enum_value_numbers_by_enum = {}
        end

        # Renders the schema as a valid `proto3` file.
        #
        # @return [String]
        def to_proto
          types = proto_types
          return "" if types.empty?

          sections = [
            %(syntax = "#{@syntax}";),
            "package #{@package_name};",
            *render_headers,
            *render_imports(types),
            render_definitions(types)
          ]

          sections.join("\n\n") + "\n"
        end

        # Exposes normalized field-number and enum-value-number mappings for writing to artifact YAML.
        #
        # @return [Hash<String, Object>]
        def field_number_mappings_for_artifact
          {
            "messages" => @proto_field_number_mappings_by_message
              .sort_by { |message_name, _| message_name }
              .to_h do |message_name, field_numbers|
                [message_name, {
                  "fields" => field_numbers.sort_by { |field_name, mapping| [mapping.field_number, field_name] }.to_h do |field_name, mapping|
                    artifact_mapping =
                      if mapping.name_in_index == field_name
                        mapping.field_number
                      else
                        {
                          "field_number" => mapping.field_number,
                          "name_in_index" => mapping.name_in_index
                        }
                      end

                    [field_name, artifact_mapping]
                  end
                }]
              end,
            "enums" => @proto_enum_value_numbers_by_enum
              .sort_by { |enum_name, _| enum_name }
              .to_h do |enum_name, value_numbers|
                [enum_name, {
                  "values" => value_numbers.sort_by { |value_name, number| [number, value_name] }.to_h
                }]
              end
          }
        end

        # Returns the stable protobuf number for a message field.
        #
        # @api private
        def field_number_for(message_name:, type_name:, public_field_name:, name_in_index:)
          mappings_for_message = @proto_field_number_mappings_by_message[message_name] ||= {}
          used_numbers = @used_field_numbers_by_message[message_name] ||= ::Set.new(mappings_for_message.values.map(&:field_number))

          mapping = mappings_for_message.fetch(public_field_name) do
            migrate_renamed_field_mapping(mappings_for_message, type_name: type_name, public_field_name: public_field_name) || begin
              next_field_number = next_available_field_number(used_numbers)
              used_numbers << next_field_number
              FieldNumberMapping.new(field_number: next_field_number, name_in_index: name_in_index)
            end
          end

          mapping = FieldNumberMapping.new(field_number: mapping.field_number, name_in_index: name_in_index) if mapping.name_in_index != name_in_index
          mappings_for_message[public_field_name] = mapping

          duplicate_field_name = mappings_for_message.find do |mapped_field_name, mapped_field_number|
            mapped_field_name != public_field_name && mapped_field_number.field_number == mapping.field_number
          end&.first

          if duplicate_field_name
            raise Errors::SchemaError, "Protobuf field-number mapping collision in message `#{message_name}`: " \
              "`#{duplicate_field_name}` and `#{public_field_name}` are both mapped to field number #{mapping.field_number}."
          end

          mapping.field_number
        end

        # Returns the stable protobuf numbers for an enum's values.
        #
        # @api private
        def enum_value_numbers_for(enum_name, value_names)
          value_numbers = @proto_enum_value_numbers_by_enum[enum_name] ||= {}
          used_numbers = used_enum_value_numbers_for(enum_name, value_numbers)

          value_names.to_h do |value_name|
            number = value_numbers.fetch(value_name) do
              next_available_enum_value_number(used_numbers).tap do |allocated|
                used_numbers << allocated
                value_numbers[value_name] = allocated
              end
            end
            [value_name, number]
          end
        end

        # Returns the label for a protobuf field under the configured syntax.
        #
        # @api private
        def field_label(repeated)
          return repeated ? "repeated " : "optional " if @syntax == "proto2"
          repeated ? "repeated " : nil
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
            .filter_map do |type|
              type.proto_definition_kind ? type.to_proto(self) : type.to_proto
            end
            .join("\n\n")
        end

        def render_imports(types)
          imports = types.filter_map do |type|
            type.protobuf_import if type.respond_to?(:protobuf_import)
          end.uniq.sort

          imports.empty? ? [] : [imports.map { |import| %(import "#{import}";) }.join("\n")]
        end

        def render_headers
          @headers.empty? ? [] : [@headers.join("\n")]
        end

        def valid_field_number?(number)
          number.between?(1, MAX_FIELD_NUMBER) && !RESERVED_FIELD_NUMBER_RANGE.cover?(number)
        end

        # Returns the smallest valid field tag not yet present in `used_numbers`, skipping the
        # protobuf-reserved 19000..19999 range. Callers maintain the set (numbers loaded from a
        # previously dumped artifact plus numbers allocated so far) so that allocation is
        # constant-time per candidate instead of rescanning all mappings.
        def next_available_field_number(used_numbers)
          candidate = 1
          candidate += 1 while used_numbers.include?(candidate) || RESERVED_FIELD_NUMBER_RANGE.cover?(candidate)
          candidate
        end

        # Returns the smallest positive enum value number not yet present in `used_numbers`.
        # Unlike field tags, enum value numbers have no protobuf-reserved range.
        def next_available_enum_value_number(used_numbers)
          candidate = 1
          candidate += 1 while used_numbers.include?(candidate)
          candidate
        end

        def used_enum_value_numbers_for(enum_name, value_numbers)
          @used_enum_value_numbers_by_enum[enum_name] ||= begin
            duplicated_numbers = value_numbers.group_by { |_, number| number }.select { |_, entries| entries.size > 1 }

            duplicated_numbers.each_value do |entries|
              value_names = entries.map(&:first).sort.map { |name| "`#{name}`" }.join(" and ")
              raise Errors::SchemaError, "Protobuf enum value-number mapping collision in enum `#{enum_name}`: " \
                "#{value_names} are both mapped to number #{entries.first.last}."
            end

            ::Set.new(value_numbers.values)
          end
        end

        def migrate_renamed_field_mapping(mappings_for_message, type_name:, public_field_name:)
          renames_for_type = renamed_public_field_names_by_type_name.fetch(type_name) { return nil }
          old_field_names = renames_for_type.fetch(public_field_name) { return nil }

          old_field_names.each do |old_field_name|
            return mappings_for_message.delete(old_field_name) if mappings_for_message.key?(old_field_name)
          end

          nil
        end

        def normalize_proto_field_number_mappings(raw_mappings)
          return {} if raw_mappings.nil?
          unless raw_mappings.is_a?(Hash)
            raise Errors::SchemaError, "Protobuf field-number mappings must be a Hash, got: #{raw_mappings.class}."
          end

          messages_hash =
            if raw_mappings.key?("messages")
              raw_mappings.fetch("messages")
            elsif raw_mappings.key?(:messages)
              raw_mappings.fetch(:messages)
            elsif raw_mappings.key?("enums") || raw_mappings.key?(:enums)
              # The hash uses the sectioned artifact format but only maps enum value numbers.
              {} # : ::Hash[untyped, untyped]
            else
              raw_mappings
            end

          unless messages_hash.is_a?(Hash)
            raise Errors::SchemaError, "Protobuf field-number mappings must have a `messages` Hash."
          end

          normalized = {} # : ::Hash[::String, fieldNumberMappingsByFieldName]

          messages_hash.each do |message_name, field_numbers|
            unless field_numbers.is_a?(Hash)
              raise Errors::SchemaError, "Field-number mapping for message `#{message_name}` must be a Hash."
            end

            normalized_fields =
              if field_numbers.key?("fields")
                field_numbers.fetch("fields")
              elsif field_numbers.key?(:fields)
                field_numbers.fetch(:fields)
              else
                field_numbers
              end

            unless normalized_fields.is_a?(Hash)
              raise Errors::SchemaError, "Field-number mapping for message `#{message_name}` must contain a `fields` Hash."
            end

            normalized_message_name = message_name.to_s
            normalized_field_numbers = {} # : fieldNumberMappingsByFieldName

            normalized_fields.each do |field_name, field_number_or_mapping|
              normalized_field_name = field_name.to_s
              normalized_field_number, normalized_name_in_index = normalize_field_number_mapping_entry(
                normalized_message_name,
                normalized_field_name,
                field_number_or_mapping
              )

              unless valid_field_number?(normalized_field_number)
                raise Errors::SchemaError, "Field-number mapping for `#{normalized_message_name}.#{normalized_field_name}` " \
                  "must be a valid protobuf field number (1 to #{MAX_FIELD_NUMBER}, excluding the reserved " \
                  "#{RESERVED_FIELD_NUMBER_RANGE.begin}-#{RESERVED_FIELD_NUMBER_RANGE.end} range), got: #{field_number_or_mapping.inspect}."
              end

              normalized_field_numbers[normalized_field_name] = FieldNumberMapping.new(
                field_number: normalized_field_number,
                name_in_index: normalized_name_in_index
              )
            end

            normalized[normalized_message_name] = normalized_field_numbers
          end

          normalized
        end

        def normalize_proto_enum_value_number_mappings(raw_mappings)
          return {} if raw_mappings.nil?

          enums_hash =
            if raw_mappings.is_a?(Hash) && raw_mappings.key?("enums")
              raw_mappings.fetch("enums")
            elsif raw_mappings.is_a?(Hash) && raw_mappings.key?(:enums)
              raw_mappings.fetch(:enums)
            else
              return {}
            end

          unless enums_hash.is_a?(Hash)
            raise Errors::SchemaError, "Protobuf enum value-number mappings must have an `enums` Hash."
          end

          normalized = {} # : ::Hash[::String, ::Hash[::String, ::Integer]]

          enums_hash.each do |enum_name, value_numbers|
            values_hash =
              if value_numbers.is_a?(Hash) && value_numbers.key?("values")
                value_numbers.fetch("values")
              elsif value_numbers.is_a?(Hash) && value_numbers.key?(:values)
                value_numbers.fetch(:values)
              else
                value_numbers
              end

            unless values_hash.is_a?(Hash)
              raise Errors::SchemaError, "Enum value-number mapping for enum `#{enum_name}` must contain a `values` Hash."
            end

            normalized_enum_name = enum_name.to_s
            normalized_value_numbers = {} # : ::Hash[::String, ::Integer]

            values_hash.each do |value_name, value_number|
              normalized_number = integral_number(value_number)

              if normalized_number.nil? || normalized_number <= 0 || normalized_number > MAX_ENUM_VALUE_NUMBER
                raise Errors::SchemaError, "Enum value-number mapping for `#{normalized_enum_name}.#{value_name}` " \
                  "must be a positive integer no greater than #{MAX_ENUM_VALUE_NUMBER} " \
                  "(0 is reserved for the `_UNSPECIFIED` value), got: #{value_number.inspect}."
              end

              normalized_value_numbers[value_name.to_s] = normalized_number
            end

            normalized[normalized_enum_name] = normalized_value_numbers
          end

          normalized
        end

        def normalize_field_number_mapping_entry(message_name, field_name, field_number_or_mapping)
          if field_number_or_mapping.is_a?(Hash)
            raw_field_number =
              if field_number_or_mapping.key?("field_number")
                field_number_or_mapping.fetch("field_number")
              elsif field_number_or_mapping.key?(:field_number)
                field_number_or_mapping.fetch(:field_number)
              else
                raise Errors::SchemaError, "Field-number mapping for `#{message_name}.#{field_name}` must include `field_number`."
              end

            raw_name_in_index =
              if field_number_or_mapping.key?("name_in_index")
                field_number_or_mapping.fetch("name_in_index")
              elsif field_number_or_mapping.key?(:name_in_index)
                field_number_or_mapping.fetch(:name_in_index)
              else
                field_name
              end

            unless raw_name_in_index.is_a?(String) || raw_name_in_index.is_a?(Symbol)
              raise Errors::SchemaError, "Field-number mapping for `#{message_name}.#{field_name}` " \
                "must use a String or Symbol `name_in_index`, got: #{raw_name_in_index.inspect}."
            end

            [integral_field_number(message_name, field_name, raw_field_number), raw_name_in_index.to_s]
          else
            [integral_field_number(message_name, field_name, field_number_or_mapping), field_name]
          end
        end

        def integral_field_number(message_name, field_name, raw_field_number)
          number = integral_number(raw_field_number)

          if number.nil?
            raise Errors::SchemaError, "Field-number mapping for `#{message_name}.#{field_name}` " \
              "must be an integer, got: #{raw_field_number.inspect}."
          end

          number
        end

        # Coerces a raw mapping number to an Integer without truncating: only `Integer` values and
        # strings that parse as integers are accepted; anything else (including floats, which
        # `Kernel#Integer` would silently truncate) returns `nil`.
        def integral_number(raw)
          case raw
          when ::Integer then raw
          when ::String then raw.match?(/\A-?\d+\z/) ? Integer(raw) : nil
          end
        end

        def renamed_public_field_names_by_type_name
          @renamed_public_field_names_by_type_name ||= @state.renamed_fields_by_type_name_and_old_field_name.to_h do |type_name, old_to_new|
            current_to_old = ::Hash.new { |h, k| h[k] = [] } # : ::Hash[::String, ::Array[::String]]

            old_to_new.each do |old_field_name, renamed_field|
              current_to_old[renamed_field.name] << old_field_name
            end

            [type_name, current_to_old]
          end
        end
      end
    end
  end
end
