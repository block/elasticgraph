# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/constants"
require "elastic_graph/proto_ingestion"
require "elastic_graph/proto_ingestion/proto_conversions"
require "elastic_graph/proto_ingestion/runtime_metadata/schema"
require "json"
require "time"

module ElasticGraph
  module ProtoIngestion
    # Prepares native protobuf messages directly into datastore records. Message descriptors supply
    # the structure once per message class, and runtime metadata supplies the ElasticGraph ingestion
    # facts that descriptors cannot express.
    # @private
    class RecordPreparer
      def initialize(schema_artifacts)
        @metadata = RuntimeMetadata::Schema.from_schema_artifacts(schema_artifacts)
        @scalar_types_by_name = schema_artifacts.runtime_metadata.scalar_types_by_name
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
      Field = ::Data.define(:name, :name_in_index, :presence_method, :list_depth, :leaf_preparer)
      private_constant :Type, :Field

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

        if (leaf_preparer = field.leaf_preparer)
          leaf_preparer.call(value)
        else
          prepare_message(value, nested_mapping)
        end
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

        case leaf.type
        when :enum
          enum_descriptor = leaf.subtype # : ::Google::Protobuf::EnumDescriptor
          enum_values = build_enum(enum_descriptor)
          leaf_preparer = ->(value) { enum_values.fetch(value, value) }
        when :message
          message_descriptor = leaf.subtype # : ::Google::Protobuf::Descriptor
          unless message_descriptor.name.start_with?("#{@metadata.package_name}.")
            leaf_preparer = ->(value) { ::Time.at(value.seconds, value.nanos, :nanosecond, in: "UTC").iso8601(DATE_TIME_PRECISION) }
          end
        else
          leaf_preparer = build_scalar_preparer(leaf, field_meta)
        end

        Field.new(name, name_in_index, presence_method, list_depth, leaf_preparer)
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

        type_name ||= DEFAULT_SCALARS_BY_PROTO_TYPE.fetch(leaf_field.type.to_s)
        preparer = @scalar_types_by_name.fetch(type_name).load_indexing_preparer.extension_class # : singleton(SchemaArtifacts::RuntimeMetadata::ScalarIndexingPreparerInterface)

        if scalar == "Untyped"
          ->(value) { preparer.prepare_for_indexing(::JSON.parse(value)) }
        else
          ->(value) { preparer.prepare_for_indexing(value) }
        end
      end

      def type_name_for(descriptor)
        descriptor.name.delete_prefix("#{@metadata.package_name}.")
      end
    end
  end
end
