# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "date"
require "elastic_graph/constants"
require "elastic_graph/proto_ingestion"
require "elastic_graph/proto_ingestion/descriptors"
require "elastic_graph/proto_ingestion/runtime_metadata/schema"
require "elastic_graph/support/valid_time_zones"
require "json"

module ElasticGraph
  module ProtoIngestion
    # Checks ElasticGraph constraints which the protobuf wire format cannot express.
    # Protobuf decoding already checks primitive wire types; this walk checks enum membership
    # and the narrower ranges/formats of ElasticGraph's built-in scalars. Generated fields are
    # optional to keep accepting historical publishers, so GraphQL nullability is not checked.
    # @private
    class RecordValidator
      DATE_TIME_STRING_REGEX = /\A(\d{4})-(\d{2})-(\d{2})[Tt ](\d{2}):(\d{2}):(\d{2})(?:\.\d+)?(?:[Zz]|[+-](\d{2}):(\d{2}))\z/
      TIMESTAMP_SECONDS_RANGE = (-62_135_596_800..253_402_300_799)
      TIMESTAMP_NANOS_RANGE = (0..999_999_999)
      WIRE_CONTRACT_SCALARS = %w[JsonSafeLong].to_set.freeze

      def self.valid_date?(value)
        /\A\d{4}-\d{2}-\d{2}\z/.match?(value) &&
          ::Date.valid_date?(value[0, 4].to_i, value[5, 2].to_i, value[8, 2].to_i)
      end

      def self.valid_date_time_string?(value)
        match = DATE_TIME_STRING_REGEX.match(value)
        return false unless match

        ::Date.valid_date?(match[1].to_i, match[2].to_i, match[3].to_i) &&
          (0..23).cover?(match[4].to_i) &&
          (0..59).cover?(match[5].to_i) &&
          (0..60).cover?(match[6].to_i) &&
          (!match[7] || ((0..23).cover?(match[7].to_i) && (0..59).cover?(match[8].to_i)))
      end

      def self.valid_timestamp?(value)
        TIMESTAMP_SECONDS_RANGE.cover?(value.seconds) && TIMESTAMP_NANOS_RANGE.cover?(value.nanos)
      end

      def self.valid_json?(value)
        ::JSON.parse(value)
        true
      rescue ::JSON::ParserError
        false
      end

      # Checks for scalars whose valid values are narrower than their protobuf wire type allows.
      SCALAR_CHECKS = {
        "JsonSafeLong" => ->(value) { (JSON_SAFE_LONG_MIN..JSON_SAFE_LONG_MAX).cover?(value) },
        "Float" => ->(value) { value.finite? },
        "Date" => ->(value) { valid_date?(value) },
        "DateTime" => ->(value) { valid_timestamp?(value) },
        "LocalTime" => ->(value) { VALID_LOCAL_TIME_REGEX.match?(value) },
        "TimeZone" => ->(value) { Support::VALID_TIME_ZONES.include?(value) },
        "Untyped" => ->(value) { valid_json?(value) }
      }.freeze # : ::Hash[::String, ^(untyped) -> boolish]

      STRING_DATE_TIME_CHECK = ->(value) { valid_date_time_string?(value) } # : ^(untyped) -> boolish

      def initialize(metadata)
        @metadata = metadata
        @types = {}
        @mutex = ::Mutex.new
      end

      # Wire-critical numeric ranges and unknown enum values are never sampled out.
      def error_for(message, path = "record", wire_contract_only: false)
        type = @mutex.synchronize { @types[message.class] ||= build_type(message.class.descriptor) }
        type.error_for(message, path, wire_contract_only)
      end

      private

      # Resolved once per protobuf message class (together with all nested message types) so
      # validation acquires `@mutex` once per root record and never re-inspects descriptors.
      # @private
      Type = ::Data.define(:fields) do
        # @implements Type

        def error_for(message, path, wire_contract_only)
          fields.each do |field|
            if (error = field.error_for(message, path, wire_contract_only))
              return error
            end
          end
          nil
        end
      end

      # Validates a message of a union or interface type by dispatching its `value` oneof
      # to the pre-resolved concrete `Type` for the active alternative.
      # @private
      AbstractType = ::Data.define(:types_by_alternative) do
        # @implements AbstractType

        def error_for(message, path, wire_contract_only)
          alternative = message.value
          return nil unless alternative

          types_by_alternative.fetch(alternative).error_for(message.public_send(alternative), path, wire_contract_only)
        end
      end

      # @private
      Field = ::Data.define(:name, :presence_method, :list_depth, :wire_contract, :error_suffix, :leaf_check, :child_type) do
        # @implements Field

        # Returns the first validation error for this field on `message`, or `nil` when valid or skipped.
        def error_for(message, path, wire_contract_only)
          return nil if wire_contract_only && !wire_contract
          return nil if presence_method && !message.public_send(presence_method)

          validate_value(message[name], list_depth, "#{path}.#{name}", wire_contract_only)
        end

        private

        def validate_value(value, depth, path, wire_contract_only)
          if depth > 0
            value.each_with_index do |item, index|
              nested = (depth > 1) ? item.values : item
              if (error = validate_value(nested, depth - 1, "#{path}[#{index}]", wire_contract_only))
                return error
              end
            end
            return nil
          end

          if (child = child_type)
            child.error_for(value, path, wire_contract_only)
          else
            check = leaf_check # : ^(untyped) -> boolish
            "#{path} #{error_suffix}" unless check.call(value)
          end
        end
      end
      private_constant :Type, :AbstractType, :Field

      def resolve_type(descriptor)
        @types[descriptor.msgclass] ||= build_type(descriptor)
      end

      def build_type(descriptor)
        if (oneof = descriptor.lookup_oneof("value"))
          types_by_alternative = {} # : ::Hash[::Symbol, Type | AbstractType]
          oneof.each do |field|
            subtype = field.subtype # : ::Google::Protobuf::Descriptor
            types_by_alternative[field.name.to_sym] = resolve_type(subtype)
          end
          return AbstractType.new(types_by_alternative)
        end

        name = Descriptors.type_name(descriptor, @metadata)
        overrides = @metadata.types_by_name[name]&.fields_by_name || {}
        fields = descriptor.filter_map do |entry|
          field = entry # : ::Google::Protobuf::FieldDescriptor
          build_field(descriptor, field, overrides[field.name])
        end
        Type.new(fields)
      end

      def build_field(descriptor, field, field_meta)
        info = Descriptors.unwrap_field(descriptor, field)
        leaf = info.leaf

        case leaf.type
        when :enum
          enum_descriptor = leaf.subtype # : ::Google::Protobuf::EnumDescriptor
          valid_symbols = enum_descriptor.to_h.keys.to_set
          Field.new(info.name, info.presence_method, info.list_depth, true, "has an unknown enum value.", ->(value) { valid_symbols.include?(value) }, nil)
        when :message
          message_descriptor = leaf.subtype # : ::Google::Protobuf::Descriptor
          if Descriptors.internal_message?(message_descriptor, @metadata)
            Field.new(info.name, info.presence_method, info.list_depth, true, nil, nil, resolve_type(message_descriptor))
          else
            build_scalar_field(info, leaf, field_meta)
          end
        else
          build_scalar_field(info, leaf, field_meta)
        end
      end

      def build_scalar_field(info, leaf_field, field_meta)
        type_name, scalar = Descriptors.scalar_info(leaf_field, field_meta, @metadata)
        check = if scalar == "DateTime" && leaf_field.type == :string
          STRING_DATE_TIME_CHECK
        else
          SCALAR_CHECKS[scalar]
        end
        return nil unless check

        Field.new(
          info.name,
          info.presence_method,
          info.list_depth,
          WIRE_CONTRACT_SCALARS.include?(scalar),
          "is not a valid #{type_name}.",
          check,
          nil
        )
      end
    end
  end
end
