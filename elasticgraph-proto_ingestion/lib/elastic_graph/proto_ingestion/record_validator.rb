# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "date"
require "elastic_graph/constants"

module ElasticGraph
  module ProtoIngestion
    # Checks ElasticGraph constraints which the protobuf wire format cannot express.
    # Protobuf decoding already checks primitive wire types; this walk checks enum membership
    # and the narrower ranges/formats of ElasticGraph's built-in scalars. Generated fields are
    # optional to keep accepting historical publishers, so GraphQL nullability is not checked.
    # @private
    class RecordValidator
      def self.valid_date?(value)
        value.is_a?(String) && /\A\d{4}-\d{2}-\d{2}\z/.match?(value) &&
          Date.valid_date?(value[0, 4].to_i, value[5, 2].to_i, value[8, 2].to_i)
      end

      def self.valid_timestamp?(value)
        value.is_a?(String) && /\A\d{4}-\d{2}-\d{2}T(?:[01]\d|2[0-3]):[0-5]\d:[0-5]\d(?:\.\d+)?(?:Z|[+-](?:[01]\d|2[0-3]):[0-5]\d)\z/.match?(value) &&
          valid_date?(value[0, 10])
      end

      # Checks for scalars whose valid values are narrower than their protobuf wire type allows.
      # `TimeZone` is also validated, against the time zones supplied by runtime metadata.
      SCALAR_CHECKS = {
        "Boolean" => ->(value) { value == true || value == false },
        "Int" => ->(value) { value.is_a?(Integer) && (INT_MIN..INT_MAX).cover?(value) },
        "JsonSafeLong" => ->(value) { value.is_a?(Integer) && (JSON_SAFE_LONG_MIN..JSON_SAFE_LONG_MAX).cover?(value) },
        "LongString" => ->(value) { value.is_a?(Integer) && (LONG_STRING_MIN..LONG_STRING_MAX).cover?(value) },
        "Float" => ->(value) { value.is_a?(Numeric) && value.finite? },
        "Date" => ->(value) { valid_date?(value) },
        "DateTime" => ->(value) { valid_timestamp?(value) },
        "LocalTime" => ->(value) { value.is_a?(String) && VALID_LOCAL_TIME_REGEX.match?(value) }
      }.freeze

      # Scalars with ingestion rules beyond their protobuf wire type.
      VALIDATED_SCALARS = [*SCALAR_CHECKS.keys, "TimeZone"].freeze

      def initialize(types, time_zones)
        @types = types
        @time_zones = time_zones.to_set
      end

      # Wire-critical numeric ranges and unknown enum values are never sampled out.
      def error_for(type, value, path = "record", wire_contract_only: false)
        return nil if value.nil?
        if type.start_with?("[")
          return "#{path} must be a list." unless value.is_a?(Array)
          item_type = type.delete_prefix("[").delete_suffix("]")
          return value.each_with_index.filter_map { |item, index| error_for(item_type, item, "#{path}[#{index}]", wire_contract_only: wire_contract_only) }.first
        end
        metadata = @types.fetch(type)
        if (subtypes = metadata["subtypes"])
          return "#{path} must identify a concrete subtype." unless value.is_a?(Hash) && subtypes.include?(value["__typename"])
          return error_for(value.fetch("__typename"), value, path, wire_contract_only: wire_contract_only)
        end
        if (fields = metadata["fields"])
          return "#{path} must be an object." unless value.is_a?(Hash)
          return fields.filter_map { |name, field| error_for(field.fetch("type"), value[name], "#{path}.#{name}", wire_contract_only: wire_contract_only) }.first
        end
        if (values = metadata["enum_values"])
          return "#{path} has an unknown enum value." unless values.value?(value)
          return nil
        end
        scalar = metadata.fetch("scalar")
        return nil if wire_contract_only && !%w[Int JsonSafeLong LongString].include?(scalar)
        "#{path} is not a valid #{type}." unless valid_scalar?(scalar, metadata.fetch("proto_type"), value)
      end

      private

      def valid_scalar?(scalar, proto_type, value)
        if (check = SCALAR_CHECKS[scalar])
          check.call(value)
        elsif scalar == "TimeZone"
          @time_zones.include?(value)
        else
          # Untyped values have already been parsed from their JSON encoding.
          scalar == "Untyped" || proto_type != "string" || value.is_a?(String)
        end
      end
    end
  end
end
