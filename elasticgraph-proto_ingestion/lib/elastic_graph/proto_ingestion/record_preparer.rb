# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/proto_ingestion/runtime_metadata/schema"
require "google/protobuf"
require "json"

module ElasticGraph
  module ProtoIngestion
    # Prepares native protobuf messages directly into datastore records. Generated metadata supplies
    # the schema facts; messages remain native until this walk writes the final index field names.
    # @private
    class RecordPreparer
      def initialize(schema_artifacts)
        @types = RuntimeMetadata::Schema.from_schema_artifacts(schema_artifacts).types_by_name
        @indexing_preparers = schema_artifacts.runtime_metadata.scalar_types_by_name.transform_values do |scalar|
          scalar.load_indexing_preparer.extension_class
        end
        @fields_by_type = @types.transform_values do |type|
          type.fields_by_name.map do |name, metadata|
            field_type = metadata.type.delete("!")
            Field.new(name, field_type, metadata.name_in_index, field_type.start_with?("[") ? nil : :"has_#{name}?")
          end
        end
        @enum_values_by_type = @types.transform_values do |type|
          values = type.enum_values_by_name.transform_keys(&:to_sym) # : Hash[Symbol, String?]
          values[type.enum_zero_value.to_sym] = nil if type.enum_zero_value
          values
        end
      end

      # Implements the indexer's record-preparer interface without an intermediate public record hash.
      # Does not mutate the native message or its nested values.
      def prepare_for_index(type_name, message, mapping_properties)
        prepare_value(type_name.delete_suffix("!"), message, mapping_properties)
      end

      private

      # Accessor names and field signatures are resolved once, without inspecting message descriptors.
      Field = ::Data.define(:name, :type, :name_in_index, :presence_method)

      def prepare_value(type_name, value, mapping_properties)
        return nil if value.nil?

        if type_name.start_with?("[")
          item_type = type_name.delete_prefix("[").delete_suffix("]")
          nested_list = item_type.start_with?("[")
          return value.map do |item|
            prepare_value(item_type, nested_list ? item.values : item, mapping_properties)
          end
        end

        metadata = @types.fetch(type_name)
        if metadata.scalar
          converted = if metadata.scalar == "Untyped"
            JSON.parse(value)
          elsif value.is_a?(Google::Protobuf::MessageExts)
            JSON.parse(Google::Protobuf.encode_json(_ = value))
          else
            value
          end
          preparer = @indexing_preparers[type_name]
          return preparer ? (_ = preparer).prepare_for_indexing(converted) : converted
        end

        unless metadata.enum_values_by_name.empty?
          return @enum_values_by_type.fetch(type_name).fetch(value, value)
        end

        unless metadata.subtypes_by_field_name.empty?
          alternative = value.value
          return nil unless alternative
          type_name = metadata.subtypes_by_field_name.fetch(alternative.to_s)
          value = value.public_send(alternative)
        end

        prepare_object(type_name, value, mapping_properties)
      end

      def prepare_object(type_name, message, mapping_properties)
        prepared = {} # : Hash[String, untyped]
        @fields_by_type.fetch(type_name).each do |field|
          next if field.presence_method && !message.public_send(field.presence_method)
          nested_mapping = mapping_properties&.dig(field.name_in_index, "properties")
          prepared[field.name_in_index] = prepare_value(field.type, message[field.name], nested_mapping)
        end

        typename_type = mapping_properties&.dig("__typename", "type")
        if typename_type && typename_type != "constant_keyword"
          prepared["__typename"] = type_name
        end
        prepared
      end
    end
  end
end
