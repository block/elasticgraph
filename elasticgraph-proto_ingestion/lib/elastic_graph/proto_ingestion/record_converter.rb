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
      def initialize(schema)
        @schema = schema
        @types = schema.types
      end

      def convert(type_name, message)
        metadata = @types.fetch(type_name)
        if metadata["subtypes"]
          variant = message.class.descriptor.lookup_oneof("value").find { |field| field.has?(message) }
          return nil unless variant
          subtype = @schema.public_type_name_for(variant.subtype.name.delete_prefix("#{@schema.package_name}."))
          return convert(subtype, variant.get(message)).merge("__typename" => subtype)
        end

        metadata.fetch("fields").filter_map do |name, field_metadata|
          field = message.class.descriptor.lookup(field_metadata.fetch("proto_name"))
          next if field.has_presence? && !field.has?(message)
          converted = convert_typed_value(field_metadata.fetch("type"), field.get(message), field)
          [name, converted]
        end.to_h
      end

      private

      def convert_typed_value(type, value, field)
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
          return nil if value == 0 || field.subtype.enummodule.lookup(0) == value || metadata.fetch("retired_enum_values").include?(value)
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
