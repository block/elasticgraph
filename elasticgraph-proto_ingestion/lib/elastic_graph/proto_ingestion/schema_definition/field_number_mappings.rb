# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/errors"
require "elastic_graph/support/from_yaml_file"
require "elastic_graph/support/json_schema/validator_factory"

module ElasticGraph
  module ProtoIngestion
    module SchemaDefinition
      # Registry of the protobuf field and enum value numbers assigned to an ElasticGraph schema.
      # Parses and validates the numbers stored in the `proto_field_numbers.yaml` artifact, hands
      # out the next available numbers for new fields and enum values, and serializes the updated
      # mappings for the next artifact dump so that numbers stay stable over time.
      class FieldNumberMappings
        extend Support::FromYamlFile

        # Stored field numbers and allocation cursor for a single protobuf message.
        #
        # @!attribute [r] field_numbers_by_name
        #   @return [Hash<String, Integer>]
        # @!attribute [r] next_number
        #   @return [Integer]
        MessageMapping = ::Data.define(:field_numbers_by_name, :next_number)
        private_constant :MessageMapping

        # Stored value numbers and allocation cursor for a single protobuf enum.
        #
        # @!attribute [r] value_numbers_by_name
        #   @return [Hash<String, Integer>]
        # @!attribute [r] next_number
        #   @return [Integer]
        EnumMapping = ::Data.define(:value_numbers_by_name, :next_number)
        private_constant :EnumMapping

        # The largest field number protobuf allows (2^29 - 1), per
        # https://protobuf.dev/programming-guides/proto3/#assigning.
        MAX_FIELD_NUMBER = 536_870_911
        # Field numbers protobuf reserves for its own implementation; they may not be used as
        # field tags, per https://protobuf.dev/programming-guides/proto3/#assigning.
        RESERVED_FIELD_NUMBER_RANGE = 19_000..19_999
        # The largest enum value number protobuf allows (the int32 maximum), per
        # https://protobuf.dev/programming-guides/proto3/#enum.
        MAX_ENUM_VALUE_NUMBER = 2_147_483_647

        # JSON schema for the `proto_field_numbers.yaml` artifact.
        JSON_SCHEMA = {
          "$schema" => "http://json-schema.org/draft-07/schema#",
          "definitions" => {
            "field_number" => {
              "type" => "integer",
              "minimum" => 1,
              "maximum" => MAX_FIELD_NUMBER,
              "not" => {
                "minimum" => RESERVED_FIELD_NUMBER_RANGE.begin,
                "maximum" => RESERVED_FIELD_NUMBER_RANGE.end
              }
            },
            "next_field_number" => {
              "type" => "integer",
              "minimum" => 1,
              "maximum" => MAX_FIELD_NUMBER + 1,
              "not" => {
                "minimum" => RESERVED_FIELD_NUMBER_RANGE.begin,
                "maximum" => RESERVED_FIELD_NUMBER_RANGE.end
              }
            },
            "enum_value_number" => {
              "type" => "integer",
              "minimum" => 1,
              "maximum" => MAX_ENUM_VALUE_NUMBER
            },
            "next_enum_value_number" => {
              "type" => "integer",
              "minimum" => 1,
              "maximum" => MAX_ENUM_VALUE_NUMBER + 1
            }
          },
          "type" => "object",
          "properties" => {
            "messages" => {
              "type" => "object",
              "additionalProperties" => {
                "type" => "object",
                "properties" => {
                  "fields" => {
                    "type" => "object",
                    "additionalProperties" => {"$ref" => "#/definitions/field_number"}
                  },
                  "next_number" => {"$ref" => "#/definitions/next_field_number"}
                },
                "required" => ["fields", "next_number"],
                "additionalProperties" => false
              }
            },
            "enums" => {
              "type" => "object",
              "additionalProperties" => {
                "type" => "object",
                "properties" => {
                  "values" => {
                    "type" => "object",
                    "additionalProperties" => {"$ref" => "#/definitions/enum_value_number"}
                  },
                  "next_number" => {"$ref" => "#/definitions/next_enum_value_number"}
                },
                "required" => ["values", "next_number"],
                "additionalProperties" => false
              }
            }
          },
          "additionalProperties" => false
        }

        VALIDATOR = Support::JSONSchema::Validator.new(
          schema: Support::JSONSchema::ValidatorFactory.new(
            schema: JSON_SCHEMA,
            sanitize_pii: false
          ).root_schema,
          sanitize_pii: false
        )
        private_constant :VALIDATOR

        # Builds an instance from parsed `proto_field_numbers.yaml`, validating its structure and
        # every mapped number.
        #
        # @param parsed_yaml [Hash, nil] parsed contents of the artifact (or a hash in the same format)
        # @return [FieldNumberMappings]
        # @raise [Errors::SchemaError] if the mappings deviate from the artifact format or contain invalid numbers
        def self.from_parsed_yaml(parsed_yaml)
          parsed_yaml ||= {} # : ::Hash[::String, untyped]
          if (validation_error = VALIDATOR.validate_with_error_message(parsed_yaml))
            raise Errors::SchemaError, "Invalid protobuf field-number mappings:\n\n#{validation_error}"
          end

          empty_section = {} # : ::Hash[untyped, untyped]

          new(
            message_mappings_by_name: parse_messages(parsed_yaml.fetch("messages", empty_section)),
            enum_mappings_by_name: parse_enums(parsed_yaml.fetch("enums", empty_section))
          )
        end

        # @param message_mappings_by_name [Hash<String, MessageMapping>] validated message mappings
        # @param enum_mappings_by_name [Hash<String, EnumMapping>] validated enum mappings
        # @api private
        def initialize(message_mappings_by_name:, enum_mappings_by_name:)
          @message_mappings_by_name = message_mappings_by_name
          @enum_mappings_by_name = enum_mappings_by_name
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
          message_mapping = @message_mappings_by_name.fetch(message_name) do
            MessageMapping.new(field_numbers_by_name: {}, next_number: 1)
          end
          field_numbers = message_mapping.field_numbers_by_name

          return field_numbers.fetch(public_field_name) if field_numbers.key?(public_field_name)

          old_field_name = previous_field_names.find { |field_name| field_numbers.key?(field_name) }
          updated_mapping =
            if old_field_name
              message_mapping.with(
                field_numbers_by_name: field_numbers
                  .except(old_field_name)
                  .merge(public_field_name => field_numbers.fetch(old_field_name))
              )
            else
              allocate_field_number(message_name, public_field_name, message_mapping)
            end

          @message_mappings_by_name = @message_mappings_by_name.merge(message_name => updated_mapping)
          updated_mapping.field_numbers_by_name.fetch(public_field_name)
        end

        # Returns the next field number that will be assigned for the given message.
        #
        # @param message_name [String]
        # @return [Integer]
        def next_field_number_for(message_name)
          @message_mappings_by_name[message_name]&.next_number || 1
        end

        # Returns field names and numbers retained in the mappings but absent from the message.
        #
        # @param message_name [String]
        # @param active_field_names [Array<String>]
        # @return [Hash<String, Integer>]
        def reserved_field_numbers_for(message_name, active_field_names)
          field_numbers = @message_mappings_by_name[message_name]&.field_numbers_by_name || {}
          reserved_numbers_by_name(field_numbers, active_field_names)
        end

        # Returns the stable protobuf numbers for an enum's values, assigning the next available
        # numbers to values that have no stored mapping.
        #
        # @param enum_name [String]
        # @param value_names [Array<String>]
        # @return [Hash<String, Integer>]
        def enum_value_numbers_for(enum_name, value_names)
          enum_mapping = @enum_mappings_by_name.fetch(enum_name) do
            EnumMapping.new(value_numbers_by_name: {}, next_number: 1)
          end
          value_numbers = enum_mapping.value_numbers_by_name
          new_value_names = value_names - value_numbers.keys
          first_new_number = enum_mapping.next_number
          last_new_number = first_new_number + new_value_names.size - 1

          if new_value_names.any? && last_new_number > MAX_ENUM_VALUE_NUMBER
            raise Errors::SchemaError, "Cannot allocate another protobuf enum value number for enum `#{enum_name}`: " \
              "the maximum enum value number (#{MAX_ENUM_VALUE_NUMBER}) has been reached."
          end

          new_value_numbers = new_value_names.each_with_index.to_h do |value_name, index|
            [value_name, first_new_number + index]
          end
          updated_value_numbers = value_numbers.merge(new_value_numbers)
          updated_mapping = enum_mapping.with(
            value_numbers_by_name: updated_value_numbers,
            next_number: last_new_number + 1
          )
          @enum_mappings_by_name = @enum_mappings_by_name.merge(enum_name => updated_mapping)

          value_names.to_h do |value_name|
            [value_name, updated_value_numbers.fetch(value_name)]
          end
        end

        # Returns the next value number that will be assigned for the given enum.
        #
        # @param enum_name [String]
        # @return [Integer]
        def next_enum_value_number_for(enum_name)
          @enum_mappings_by_name[enum_name]&.next_number || 1
        end

        # Returns value names and numbers retained in the mappings but absent from the enum.
        #
        # @param enum_name [String]
        # @param active_value_names [Array<String>]
        # @return [Hash<String, Integer>]
        def reserved_enum_value_numbers_for(enum_name, active_value_names)
          value_numbers = @enum_mappings_by_name[enum_name]&.value_numbers_by_name || {}
          reserved_numbers_by_name(value_numbers, active_value_names)
        end

        # Returns the previously pinned numbers for a protobuf enum.
        #
        # @param enum_name [String]
        # @return [Hash<String, Integer>]
        def pinned_enum_value_numbers(enum_name)
          @enum_mappings_by_name[enum_name]&.value_numbers_by_name || {}
        end

        # Serializes the mappings back to the `proto_field_numbers.yaml` artifact format, with
        # messages and enums sorted by name and their fields and values sorted by number.
        #
        # @return [Hash<String, Object>]
        def to_dumpable_hash
          {
            "messages" => @message_mappings_by_name
              .sort_by(&:first)
              .to_h do |message_name, message_mapping|
                [message_name, {
                  "fields" => message_mapping.field_numbers_by_name.sort_by { |field_name, number| [number, field_name] }.to_h,
                  "next_number" => message_mapping.next_number
                }]
              end,
            "enums" => @enum_mappings_by_name
              .sort_by(&:first)
              .to_h do |enum_name, enum_mapping|
                [enum_name, {
                  "values" => enum_mapping.value_numbers_by_name.sort_by { |value_name, number| [number, value_name] }.to_h,
                  "next_number" => enum_mapping.next_number
                }]
              end
          }
        end

        private

        def reserved_numbers_by_name(numbers_by_name, active_names)
          numbers_by_name
            .except(*active_names)
            .sort_by { |name, number| [number, name] }
            .to_h
        end

        # Returns a message mapping with the stored allocation cursor assigned to `field_name` and
        # advanced past the claimed number and protobuf's reserved 19000..19999 range.
        def allocate_field_number(message_name, field_name, message_mapping)
          field_number = message_mapping.next_number
          if field_number > MAX_FIELD_NUMBER
            raise Errors::SchemaError, "Cannot allocate another protobuf field number for message `#{message_name}`: " \
              "the maximum field number (#{MAX_FIELD_NUMBER}) has been reached."
          end

          next_number = field_number + 1
          if RESERVED_FIELD_NUMBER_RANGE.cover?(next_number)
            next_number = RESERVED_FIELD_NUMBER_RANGE.end + 1
          end

          message_mapping.with(
            field_numbers_by_name: message_mapping.field_numbers_by_name.merge(field_name => field_number),
            next_number: next_number
          )
        end

        private_class_method def self.parse_messages(messages_section)
          messages_section.to_h do |message_name, message_entry|
            fields = message_entry.fetch("fields") # : ::Hash[::String, ::Integer]

            verify_no_number_collisions(
              fields,
              "field-number mapping collision in message `#{message_name}`"
            )

            next_number = message_entry.fetch("next_number") # : ::Integer

            verify_next_number_is_after_mapped_numbers("message `#{message_name}`", next_number, fields)
            [message_name, MessageMapping.new(field_numbers_by_name: fields, next_number: next_number)]
          end
        end

        private_class_method def self.parse_enums(enums_section)
          enums_section.to_h do |enum_name, enum_entry|
            values = enum_entry.fetch("values") # : ::Hash[::String, ::Integer]
            verify_no_number_collisions(values, "enum value-number mapping collision in enum `#{enum_name}`")

            next_number = enum_entry.fetch("next_number") # : ::Integer
            verify_next_number_is_after_mapped_numbers("enum `#{enum_name}`", next_number, values)
            [enum_name, EnumMapping.new(value_numbers_by_name: values, next_number: next_number)]
          end
        end

        private_class_method def self.verify_next_number_is_after_mapped_numbers(mapping_description, next_number, numbers)
          max_number = numbers.values.max
          if max_number && next_number <= max_number
            raise Errors::SchemaError, "Protobuf `next_number` for #{mapping_description} must be greater than " \
              "every mapped number (maximum: #{max_number}), got: #{next_number}."
          end

          nil
        end

        private_class_method def self.verify_no_number_collisions(numbers_by_name, collision_description)
          numbers_by_name.group_by(&:last).each_value do |entries|
            next if entries.size < 2

            names = entries.map(&:first).sort.map { |name| "`#{name}`" }.join(" and ")
            raise Errors::SchemaError, "Protobuf #{collision_description}: " \
              "#{names} are both mapped to number #{entries.first.last}."
          end
        end
      end
    end
  end
end
