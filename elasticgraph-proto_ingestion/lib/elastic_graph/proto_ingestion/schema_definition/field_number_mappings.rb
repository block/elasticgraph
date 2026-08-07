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
        # Stored field numbers and allocation cursor for a single protobuf message.
        #
        # @!attribute [r] field_numbers_by_name
        #   @return [Hash<String, Integer>]
        # @!attribute [r] next_number
        #   @return [Integer]
        MessageMapping = ::Data.define(:field_numbers_by_name, :next_number)
        private_constant :MessageMapping

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
          return new(message_mappings_by_name: {}, value_numbers_by_enum: {}) if artifact.nil?

          unless artifact.is_a?(::Hash)
            raise Errors::SchemaError, "Protobuf field-number mappings must be a Hash, got: #{artifact.class}."
          end

          verify_known_keys(artifact, ["messages", "enums"], "protobuf field-number mappings")

          empty_section = {} # : ::Hash[untyped, untyped]

          new(
            message_mappings_by_name: parse_messages(artifact.fetch("messages", empty_section)),
            value_numbers_by_enum: parse_enums(artifact.fetch("enums", empty_section))
          )
        end

        # @param message_mappings_by_name [Hash<String, MessageMapping>] validated message mappings
        # @param value_numbers_by_enum [Hash<String, Hash<String, Integer>>] validated enum value numbers
        # @api private
        def initialize(message_mappings_by_name:, value_numbers_by_enum:)
          @message_mappings_by_name = message_mappings_by_name
          @value_numbers_by_enum = value_numbers_by_enum
          @used_enum_value_numbers_by_enum = {}
        end

        # Returns the stable protobuf number for a message field, assigning the message's stored
        # `next_number` if the field has no mapping. When the field was renamed, the mapping
        # stored under one of its `previous_field_names` (and its number) carries over.
        #
        # @param message_name [String]
        # @param public_field_name [String]
        # @param previous_field_names [Array<String>] old public names of the field, if renamed
        # @return [Integer]
        def field_number_for(message_name:, public_field_name:, previous_field_names:)
          message_mapping = @message_mappings_by_name[message_name] ||= MessageMapping.new(
            field_numbers_by_name: {},
            next_number: 1
          )
          field_numbers = message_mapping.field_numbers_by_name

          return field_numbers.fetch(public_field_name) if field_numbers.key?(public_field_name)

          if (renamed_field_number = migrate_renamed_field_number(field_numbers, previous_field_names))
            return field_numbers[public_field_name] = renamed_field_number
          end

          field_numbers[public_field_name] = allocate_field_number(message_name, message_mapping)
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
            number = value_numbers[value_name] ||= allocate_enum_value_number(used_numbers)
            [value_name, number]
          end
        end

        # Serializes the mappings back to the `proto_field_numbers.yaml` artifact format, with
        # messages and enums sorted by name and their fields and values sorted by number.
        #
        # @return [Hash<String, Object>]
        def to_artifact
          {
            "messages" => @message_mappings_by_name
              .sort_by(&:first)
              .to_h do |message_name, message_mapping|
                [message_name, {
                  "fields" => message_mapping.field_numbers_by_name.sort_by { |field_name, number| [number, field_name] }.to_h,
                  "next_number" => message_mapping.next_number
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

        def used_enum_value_numbers_for(enum_name, value_numbers)
          @used_enum_value_numbers_by_enum[enum_name] ||= ::Set.new(value_numbers.values)
        end

        # Claims and returns the message's stored allocation cursor, advancing it past the claimed
        # number and protobuf's reserved 19000..19999 range.
        def allocate_field_number(message_name, message_mapping)
          field_number = message_mapping.next_number
          if field_number > MAX_FIELD_NUMBER
            raise Errors::SchemaError, "Cannot allocate another protobuf field number for message `#{message_name}`: " \
              "the maximum field number (#{MAX_FIELD_NUMBER}) has been reached."
          end

          next_number = field_number + 1
          if RESERVED_FIELD_NUMBER_RANGE.cover?(next_number)
            next_number = RESERVED_FIELD_NUMBER_RANGE.end + 1
          end

          @message_mappings_by_name[message_name] = message_mapping.with(next_number: next_number)
          field_number
        end

        # Claims and returns the smallest positive enum value number not yet present in
        # `used_numbers`. Unlike field tags, enum value numbers have no protobuf-reserved range.
        def allocate_enum_value_number(used_numbers)
          candidate = 1
          candidate += 1 while used_numbers.include?(candidate)
          used_numbers << candidate
          candidate
        end

        def migrate_renamed_field_number(field_numbers, previous_field_names)
          previous_field_names.each do |old_field_name|
            field_number = field_numbers.delete(old_field_name)
            return field_number if field_number
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

            verify_known_keys(message_entry, ["fields", "next_number"], "field-number mapping for message `#{message_name}`")

            fields = message_entry["fields"]
            unless fields.is_a?(::Hash)
              raise Errors::SchemaError, "Field-number mapping for message `#{message_name}` must contain a `fields` Hash."
            end

            parsed_fields = fields.to_h do |field_name, field_number|
              [field_name, validated_field_number(message_name, field_name, field_number)]
            end

            verify_no_number_collisions(
              parsed_fields,
              "field-number mapping collision in message `#{message_name}`"
            )

            next_number =
              if message_entry.key?("next_number")
                validated_next_number(message_name, message_entry.fetch("next_number"), parsed_fields)
              else
                candidate = (parsed_fields.values.max || 0) + 1
                RESERVED_FIELD_NUMBER_RANGE.cover?(candidate) ? RESERVED_FIELD_NUMBER_RANGE.end + 1 : candidate
              end

            [message_name, MessageMapping.new(field_numbers_by_name: parsed_fields, next_number: next_number)]
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

        private_class_method def self.validated_next_number(message_name, next_number, field_numbers)
          unless next_number.is_a?(::Integer)
            raise Errors::SchemaError, "Protobuf `next_number` for message `#{message_name}` " \
              "must be an integer, got: #{next_number.inspect}."
          end

          unless next_number.between?(1, MAX_FIELD_NUMBER + 1) && !RESERVED_FIELD_NUMBER_RANGE.cover?(next_number)
            raise Errors::SchemaError, "Protobuf `next_number` for message `#{message_name}` must be between 1 and " \
              "#{MAX_FIELD_NUMBER + 1}, excluding the reserved #{RESERVED_FIELD_NUMBER_RANGE.begin}-" \
              "#{RESERVED_FIELD_NUMBER_RANGE.end} range, got: #{next_number.inspect}."
          end

          max_field_number = field_numbers.values.max
          if max_field_number && next_number <= max_field_number
            raise Errors::SchemaError, "Protobuf `next_number` for message `#{message_name}` must be greater than " \
              "every mapped field number (maximum: #{max_field_number}), got: #{next_number}."
          end

          next_number
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
