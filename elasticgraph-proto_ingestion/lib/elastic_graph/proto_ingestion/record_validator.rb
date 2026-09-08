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
    # Protobuf decoding already checks primitive wire types; this walk checks nullability,
    # enum membership, and the narrower ranges/formats of ElasticGraph's built-in scalars.
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

      def initialize(types)
        @types = types
      end

      def error_for(type, value, path = "record")
        if value.nil?
          return "#{path} must not be null." if type.end_with?("!")
          return nil
        end
        type = type.delete_suffix("!")
        if type.start_with?("[")
          return "#{path} must be a list." unless value.is_a?(Array)
          item_type = type.delete_prefix("[").delete_suffix("]")
          return value.each_with_index.filter_map { |item, index| error_for(item_type, item, "#{path}[#{index}]") }.first
        end
        metadata = @types.fetch(type)
        if (subtypes = metadata["subtypes"])
          return "#{path} must identify a concrete subtype." unless value.is_a?(Hash) && subtypes.include?(value["__typename"])
          return error_for(value.fetch("__typename"), value, path)
        end
        if (fields = metadata["fields"])
          return "#{path} must be an object." unless value.is_a?(Hash)
          return fields.filter_map { |name, field| error_for(field.fetch("type"), value[name], "#{path}.#{name}") }.first
        end
        if (values = metadata["enum_values"])
          return "#{path} has an unknown enum value." unless values.value?(value)
          return nil
        end
        if (allowed_values = metadata["allowed_values"]) && !allowed_values.include?(value)
          return "#{path} is not a valid #{type}."
        end
        "#{path} is not a valid #{type}." unless valid_scalar?(metadata.fetch("scalar"), metadata.fetch("proto_type"), value)
      end

      private

      def valid_scalar?(scalar, proto_type, value)
        case scalar
        when "Boolean" then value == true || value == false
        when "Int" then value.is_a?(Integer) && (INT_MIN..INT_MAX).cover?(value)
        when "JsonSafeLong" then value.is_a?(Integer) && (JSON_SAFE_LONG_MIN..JSON_SAFE_LONG_MAX).cover?(value)
        when "LongString" then value.is_a?(Integer) && (LONG_STRING_MIN..LONG_STRING_MAX).cover?(value)
        when "Float" then value.is_a?(Numeric) && value.finite?
        when "Date" then self.class.valid_date?(value)
        when "DateTime" then self.class.valid_timestamp?(value)
        when "LocalTime" then value.is_a?(String) && VALID_LOCAL_TIME_REGEX.match?(value)
        when "Untyped" then true
        else
          proto_type != "string" || value.is_a?(String)
        end
      end
    end
  end
end
