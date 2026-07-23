# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/errors"

module ElasticGraph
  module ProtoIngestion
    module SchemaDefinition
      # Registry of the protobuf field and enum value numbers assigned to an ElasticGraph schema.
      # Parses and validates the numbers stored in the `proto_field_numbers.yaml` artifact, hands
      # out the next available numbers for new fields and enum values, and serializes the updated
      # mappings for the next artifact dump so that numbers stay stable over time.
      class FieldNumberMappings
        # Stored mapping for a single message field.
        #
        # @!attribute [r] field_number
        #   @return [Integer]
        # @!attribute [r] name_in_index
        #   @return [String]
        FieldMapping = ::Data.define(:field_number, :name_in_index)

        # The largest field number protobuf allows (2^29 - 1), per
        # https://protobuf.dev/programming-guides/proto3/#assigning.
        MAX_FIELD_NUMBER = 536_870_911
        # Field numbers protobuf reserves for its own implementation; they may not be used as
        # field tags, per https://protobuf.dev/programming-guides/proto3/#assigning.
        RESERVED_FIELD_NUMBER_RANGE = 19_000..19_999
        # The largest enum value number protobuf allows (the int32 maximum), per
        # https://protobuf.dev/programming-guides/proto3/#enum.
        MAX_ENUM_VALUE_NUMBER = 2_147_483_647

        # Builds an instance from mappings in the `proto_field_numbers.yaml` artifact format,
        # validating the structure and every mapped number.
        #
        # @param artifact [Hash, nil] parsed contents of the artifact (or a hash in the same format)
        # @return [FieldNumberMappings]
        # @raise [Errors::SchemaError] if the mappings deviate from the artifact format or contain invalid numbers
        def self.from_artifact(artifact)
          return new(mappings_by_message: {}, value_numbers_by_enum: {}) if artifact.nil?

          unless artifact.is_a?(::Hash)
            raise Errors::SchemaError, "Protobuf field-number mappings must be a Hash, got: #{artifact.class}."
          end

          verify_known_keys(artifact, ["messages", "enums"], "protobuf field-number mappings")

          empty_section = {} # : ::Hash[untyped, untyped]

          new(
            mappings_by_message: parse_messages(artifact.fetch("messages", empty_section)),
            value_numbers_by_enum: parse_enums(artifact.fetch("enums", empty_section))
          )
        end

        # @param mappings_by_message [Hash<String, Hash<String, FieldMapping>>] validated field mappings
        # @param value_numbers_by_enum [Hash<String, Hash<String, Integer>>] validated enum value numbers
        # @api private
        def initialize(mappings_by_message:, value_numbers_by_enum:)
          @mappings_by_message = mappings_by_message
          @value_numbers_by_enum = value_numbers_by_enum
          @used_field_numbers_by_message = {}
          @used_enum_value_numbers_by_enum = {}
        end

        # Returns the stable protobuf number for a message field, assigning the next available
        # number if the field has no stored mapping. When the field was renamed, the mapping
        # stored under one of its `previous_field_names` (and its number) carries over.
        #
        # @param message_name [String]
        # @param public_field_name [String]
        # @param name_in_index [String]
        # @param previous_field_names [Array<String>] old public names of the field, if renamed
        # @return [Integer]
        def field_number_for(message_name:, public_field_name:, name_in_index:, previous_field_names:)
          mappings_for_message = @mappings_by_message[message_name] ||= {}
          used_numbers = used_field_numbers_for(message_name, mappings_for_message)

          mapping = mappings_for_message.fetch(public_field_name) do
            migrate_renamed_field_mapping(mappings_for_message, previous_field_names) || begin
              next_field_number = next_available_field_number(used_numbers)
              used_numbers << next_field_number
              FieldMapping.new(field_number: next_field_number, name_in_index: name_in_index)
            end
          end

          mapping = mapping.with(name_in_index: name_in_index) if mapping.name_in_index != name_in_index
          mappings_for_message[public_field_name] = mapping

          mapping.field_number
        end

        # Returns the stable protobuf numbers for an enum's values, assigning the next available
        # numbers to values that have no stored mapping.
        #
        # @param enum_name [String]
        # @param value_names [Array<String>]
        # @return [Hash<String, Integer>]
        def enum_value_numbers_for(enum_name, value_names)
          value_numbers = @value_numbers_by_enum[enum_name] ||= {}
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

        # Serializes the mappings back to the `proto_field_numbers.yaml` artifact format, with
        # messages and enums sorted by name and their fields and values sorted by number.
        #
        # @return [Hash<String, Object>]
        def to_artifact
          {
            "messages" => @mappings_by_message
              .sort_by(&:first)
              .to_h do |message_name, mappings_by_field_name|
                [message_name, {
                  "fields" => mappings_by_field_name.sort_by { |field_name, mapping| [mapping.field_number, field_name] }.to_h do |field_name, mapping|
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
            "enums" => @value_numbers_by_enum
              .sort_by(&:first)
              .to_h do |enum_name, value_numbers|
                [enum_name, {
                  "values" => value_numbers.sort_by { |value_name, number| [number, value_name] }.to_h
                }]
              end
          }
        end

        private

        def used_field_numbers_for(message_name, mappings_for_message)
          @used_field_numbers_by_message[message_name] ||= ::Set.new(mappings_for_message.each_value.map(&:field_number))
        end

        def used_enum_value_numbers_for(enum_name, value_numbers)
          @used_enum_value_numbers_by_enum[enum_name] ||= ::Set.new(value_numbers.values)
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

        def migrate_renamed_field_mapping(mappings_for_message, previous_field_names)
          previous_field_names.each do |old_field_name|
            mapping = mappings_for_message.delete(old_field_name)
            return mapping if mapping
          end

          nil
        end

        private_class_method def self.parse_messages(messages_section)
          unless messages_section.is_a?(::Hash)
            raise Errors::SchemaError, "Protobuf field-number mappings must have a `messages` Hash."
          end

          messages_section.to_h do |message_name, message_entry|
            unless message_entry.is_a?(::Hash)
              raise Errors::SchemaError, "Field-number mapping for message `#{message_name}` must be a Hash."
            end

            verify_known_keys(message_entry, ["fields"], "field-number mapping for message `#{message_name}`")

            fields = message_entry["fields"]
            unless fields.is_a?(::Hash)
              raise Errors::SchemaError, "Field-number mapping for message `#{message_name}` must contain a `fields` Hash."
            end

            parsed_fields = fields.to_h do |field_name, field_entry|
              [field_name, parse_field_entry(message_name, field_name, field_entry)]
            end

            verify_no_number_collisions(
              parsed_fields.transform_values(&:field_number),
              "field-number mapping collision in message `#{message_name}`"
            )

            [message_name, parsed_fields]
          end
        end

        private_class_method def self.parse_enums(enums_section)
          unless enums_section.is_a?(::Hash)
            raise Errors::SchemaError, "Protobuf enum value-number mappings must have an `enums` Hash."
          end

          enums_section.to_h do |enum_name, enum_entry|
            unless enum_entry.is_a?(::Hash)
              raise Errors::SchemaError, "Enum value-number mapping for enum `#{enum_name}` must be a Hash."
            end

            verify_known_keys(enum_entry, ["values"], "enum value-number mapping for enum `#{enum_name}`")

            values = enum_entry["values"]
            unless values.is_a?(::Hash)
              raise Errors::SchemaError, "Enum value-number mapping for enum `#{enum_name}` must contain a `values` Hash."
            end

            parsed_values = values.to_h do |value_name, value_number|
              unless value_number.is_a?(::Integer) && value_number.between?(1, MAX_ENUM_VALUE_NUMBER)
                raise Errors::SchemaError, "Enum value-number mapping for `#{enum_name}.#{value_name}` " \
                  "must be a positive integer no greater than #{MAX_ENUM_VALUE_NUMBER} " \
                  "(0 is reserved for the `_UNSPECIFIED` value), got: #{value_number.inspect}."
              end

              [value_name, value_number]
            end

            verify_no_number_collisions(parsed_values, "enum value-number mapping collision in enum `#{enum_name}`")

            [enum_name, parsed_values]
          end
        end

        private_class_method def self.parse_field_entry(message_name, field_name, field_entry)
          unless field_entry.is_a?(::Hash)
            return FieldMapping.new(
              field_number: validated_field_number(message_name, field_name, field_entry),
              name_in_index: field_name
            )
          end

          verify_known_keys(field_entry, ["field_number", "name_in_index"], "field-number mapping for `#{message_name}.#{field_name}`")

          field_number = field_entry.fetch("field_number") do
            raise Errors::SchemaError, "Field-number mapping for `#{message_name}.#{field_name}` must include `field_number`."
          end

          name_in_index = field_entry.fetch("name_in_index", field_name)
          unless name_in_index.is_a?(::String)
            raise Errors::SchemaError, "Field-number mapping for `#{message_name}.#{field_name}` " \
              "must use a String `name_in_index`, got: #{name_in_index.inspect}."
          end

          FieldMapping.new(
            field_number: validated_field_number(message_name, field_name, field_number),
            name_in_index: name_in_index
          )
        end

        private_class_method def self.validated_field_number(message_name, field_name, field_number)
          unless field_number.is_a?(::Integer)
            raise Errors::SchemaError, "Field-number mapping for `#{message_name}.#{field_name}` " \
              "must be an integer, got: #{field_number.inspect}."
          end

          unless field_number.between?(1, MAX_FIELD_NUMBER) && !RESERVED_FIELD_NUMBER_RANGE.cover?(field_number)
            raise Errors::SchemaError, "Field-number mapping for `#{message_name}.#{field_name}` " \
              "must be a valid protobuf field number (1 to #{MAX_FIELD_NUMBER}, excluding the reserved " \
              "#{RESERVED_FIELD_NUMBER_RANGE.begin}-#{RESERVED_FIELD_NUMBER_RANGE.end} range), got: #{field_number.inspect}."
          end

          field_number
        end

        private_class_method def self.verify_no_number_collisions(numbers_by_name, collision_description)
          numbers_by_name.group_by(&:last).each_value do |entries|
            next if entries.size < 2

            names = entries.map(&:first).sort.map { |name| "`#{name}`" }.join(" and ")
            raise Errors::SchemaError, "Protobuf #{collision_description}: " \
              "#{names} are both mapped to number #{entries.first.last}."
          end
        end

        private_class_method def self.verify_known_keys(hash, known_keys, description)
          unknown_keys = hash.keys - known_keys
          return if unknown_keys.empty?

          raise Errors::SchemaError, "Unknown key(s) in #{description}: #{unknown_keys.map(&:inspect).join(", ")}. " \
            "Supported keys: #{known_keys.map { |key| "`#{key}`" }.join(", ")}."
        end
      end
    end
  end
end
