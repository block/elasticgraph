# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "google/protobuf"
require "json"

module ElasticGraph
  module ProtoIngestion
    # Converts protobuf reflection values to ElasticGraph's public record representation.
    # @private
    class RecordConverter
      def initialize(types)
        @types = types
      end

      def convert(type_name, message)
        metadata = @types.fetch(type_name)
        if metadata["subtypes"]
          variant = message.class.descriptor.lookup_oneof("value").find { |field| field.has?(message) }
          return nil unless variant
          subtype = variant.subtype.name.split(".").last
          return convert(subtype, variant.get(message)).merge("__typename" => subtype)
        end

        metadata.fetch("fields").to_h do |name, field_metadata|
          field = message.class.descriptor.lookup(name)
          value = field.get(message)
          value = nil if field.has_presence? && !field.has?(message)
          converted = convert_typed_value(field_metadata.fetch("type"), value, field)
          [name, converted]
        end
      end

      private

      def convert_typed_value(type, value, field)
        return nil if value.nil?
        type = type.delete_suffix("!")
        return convert_value(type, value, field) unless type.start_with?("[")
        if value.class.respond_to?(:descriptor)
          field = value.class.descriptor.lookup("values")
          value = field.get(value)
        end
        item_type = type.delete_prefix("[").delete_suffix("]")
        value.map { |item| convert_typed_value(item_type, item, field) }
      end

      def convert_value(type_name, value, field)
        metadata = @types.fetch(type_name)
        if (enum_values = metadata["enum_values"])
          return nil if value == 0 || field.subtype.lookup_value(0) == value
          return enum_values.fetch(value.to_s, value)
        end
        return convert(type_name, value) unless metadata["scalar"]
        return JSON.parse(value) if metadata.fetch("scalar") == "Untyped"
        return JSON.parse(Google::Protobuf.encode_json(value)) if field.type == :message
        value
      end
    end
  end
end
