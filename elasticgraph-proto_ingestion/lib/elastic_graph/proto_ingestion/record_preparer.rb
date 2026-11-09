# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/proto_ingestion"
require "elastic_graph/proto_ingestion/proto_conversions"
require "elastic_graph/proto_ingestion/runtime_metadata/schema"
require "google/protobuf"
require "json"

module ElasticGraph
  module ProtoIngestion
    # Prepares native protobuf messages directly into datastore records. Message descriptors supply
    # the structure once per message class, and runtime metadata supplies the ElasticGraph ingestion
    # facts that descriptors cannot express.
    # @private
    class RecordPreparer
      def initialize(schema_artifacts)
        @metadata = RuntimeMetadata::Schema.from_schema_artifacts(schema_artifacts)
        @indexing_preparers = schema_artifacts.runtime_metadata.scalar_types_by_name.transform_values do |scalar|
          scalar.load_indexing_preparer.extension_class
        end
        @types = {}
        @enums = {}
        @mutex = ::Mutex.new
      end

      # Implements the indexer's record-preparer interface without an intermediate public record hash.
      # Does not mutate the native message or its nested values.
      def prepare_for_index(_type_name, message, mapping_properties)
        prepare_message(message, mapping_properties)
      end

      private

      # Resolved once per protobuf message class so subsequent records do not inspect descriptors.
      Type = ::Data.define(:name, :fields)
      Field = ::Data.define(:name, :name_in_index, :presence_method, :list_depth, :nested_message, :leaf_preparer)

      def prepare_message(message, mapping_properties)
        return nil if message.nil?

        type = @mutex.synchronize { @types[message.class] ||= build_type(message.class.descriptor) }
        fields = type.fields
        unless fields
          alternative = message.value
          return nil unless alternative

          return prepare_message(message.public_send(alternative), mapping_properties)
        end

        prepared = {} # : Hash[String, untyped]
        fields.each do |field|
          next if field.presence_method && !message.public_send(field.presence_method)

          nested_mapping = mapping_properties&.dig(field.name_in_index, "properties")
          prepared[field.name_in_index] = prepare_value(field, message[field.name], field.list_depth, nested_mapping)
        end

        typename_type = mapping_properties&.dig("__typename", "type")
        if typename_type && typename_type != "constant_keyword"
          prepared["__typename"] = type.name
        end

        prepared
      end

      def prepare_value(field, value, depth, nested_mapping)
        if depth > 0
          return value.map do |item|
            prepare_value(field, (depth > 1) ? item.values : item, depth - 1, nested_mapping)
          end
        end

        return prepare_message(value, nested_mapping) if field.nested_message

        (_ = field.leaf_preparer).call(value)
      end

      def build_type(descriptor)
        name = type_name_for(descriptor)
        return Type.new(name, nil) if descriptor.lookup_oneof("value")

        overrides = @metadata.types_by_name[name]&.fields_by_name || {}
        fields = descriptor.map do |entry|
          field = entry # : ::Google::Protobuf::FieldDescriptor
          build_field(descriptor, field, overrides[field.name])
        end

        Type.new(name, fields)
      end

      def build_field(descriptor, field, field_meta)
        name = field.name
        name_in_index = field_meta&.name_in_index || name
        presence_method = (field.label == :repeated) ? nil : :"has_#{name}?"

        list_depth = 0
        leaf = field
        while leaf.label == :repeated
          list_depth += 1
          break unless leaf.type == :message

          wrapper = leaf.subtype # : ::Google::Protobuf::Descriptor
          break unless wrapper.name.start_with?("#{descriptor.name}.")

          leaf = wrapper.lookup("values") # : ::Google::Protobuf::FieldDescriptor
        end

        if leaf.type == :enum
          enum_descriptor = leaf.subtype # : ::Google::Protobuf::EnumDescriptor
          enum_values = build_enum(enum_descriptor)
          Field.new(name, name_in_index, presence_method, list_depth, false, ->(value) { enum_values.fetch(value, value) })
        elsif leaf.type == :message && (_ = leaf.subtype).name.start_with?("#{@metadata.package_name}.")
          Field.new(name, name_in_index, presence_method, list_depth, true, nil)
        else
          Field.new(name, name_in_index, presence_method, list_depth, false, build_scalar_preparer(leaf, field_meta))
        end
      end

      def build_enum(descriptor)
        @enums[descriptor] ||= begin
          name = type_name_for(descriptor)
          overrides = @metadata.types_by_name[name]&.non_standard_enum_values_by_name || {}
          entries = descriptor.to_h
          prefix = entries.key(0).to_s.delete_suffix("_UNSPECIFIED")
          values = {} # : Hash[Symbol | Integer, String?]

          entries.each do |symbol, number|
            key = symbol.to_s
            value = (number == 0) ? nil : (overrides[key] || ProtoConversions.enum_value_to_eg_name(key, prefix))
            # JRuby can expose repeated enum values as numbers rather than symbols.
            values[symbol] = values[number] = value
          end

          values
        end
      end

      def build_scalar_preparer(leaf_field, field_meta)
        if (type_name = field_meta&.type)
          scalar = @metadata.types_by_name.fetch(type_name).scalar
        end

        proto_type = leaf_field.subtype&.name || leaf_field.type.to_s
        scalar ||= DEFAULT_SCALARS_BY_PROTO_TYPE.fetch(proto_type)
        type_name ||= scalar
        preparer = @indexing_preparers[type_name]

        if scalar == "Untyped"
          ->(value) { prepare_scalar(preparer, ::JSON.parse(value)) }
        elsif leaf_field.type == :message
          ->(value) { prepare_scalar(preparer, ::JSON.parse(::Google::Protobuf.encode_json(value))) }
        else
          ->(value) { prepare_scalar(preparer, value) }
        end
      end

      def prepare_scalar(preparer, value)
        preparer ? (_ = preparer).prepare_for_indexing(value) : value
      end

      def type_name_for(descriptor)
        descriptor.name.delete_prefix("#{@metadata.package_name}.")
      end
    end
  end
end
