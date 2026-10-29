# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/errors"
require "elastic_graph/indexer/record_preparer"
require "elastic_graph/proto_ingestion"
require "elastic_graph/proto_ingestion/proto_conversions"
require "elastic_graph/proto_ingestion/runtime_metadata/schema"

module ElasticGraph
  module ProtoIngestion
    # Describes indexed protobuf records. Structure comes from the protobuf descriptors of the
    # messages being ingested; runtime metadata supplies only what those descriptors cannot express:
    # private index field names, scalars with ingestion rules beyond their wire type, enum value names
    # that casing cannot recover.
    # @private
    class RuntimeSchema
      # @dynamic types, package_name
      attr_reader :types, :package_name

      def initialize(schema_artifacts)
        extension = schema_artifacts.runtime_metadata.indexer_extension_modules.find do |candidate|
          candidate.extension_ref.fetch("name") == "ElasticGraph::ProtoIngestion::IndexerExtension"
        end
        unless extension
          raise Errors::ConfigError, "Protobuf runtime metadata is missing. Enable ProtoIngestion::SchemaDefinition::APIExtension and dump schema artifacts."
        end
        @metadata = RuntimeMetadata::Schema.from_hash(extension.extension_ref.fetch("config"))
        @package_name = @metadata.package_name
        @indexing_preparers = schema_artifacts.runtime_metadata.scalar_types_by_name.transform_values do |scalar|
          scalar.load_indexing_preparer.extension_class
        end
        # Filled in from descriptors as messages arrive; shared with the converter and validator.
        @types = {}
      end

      # Adds a message type, and every type it references, to {#types}.
      # @param descriptor [Google::Protobuf::Descriptor]
      # @return [String] the type's name
      def register(descriptor)
        name = descriptor.name.delete_prefix("#{package_name}.")
        return name if types.key?(name)

        # Register before following references, since protobuf messages may be recursive.
        types[name] = {}
        if (oneof = descriptor.lookup_oneof("value"))
          types[name] = {"subtypes" => oneof.map { |field| register(field.subtype) }}
        else
          overrides = @metadata.types_by_name[name]&.fields_by_name || {}
          fields = descriptor.to_h do |entry|
            # Message descriptors yield only fields; oneofs are reached through `lookup_oneof`.
            field = entry # : ::Google::Protobuf::FieldDescriptor
            field_overrides = overrides[field.name]
            public_name = field.name
            [public_name, {
              "type" => field_type_for(descriptor, field, field_overrides),
              "name_in_index" => field_overrides&.name_in_index || public_name
            }]
          end
          types[name] = {"fields" => fields}
          @record_preparer = nil
        end

        name
      end

      # @return [ElasticGraph::Indexer::RecordPreparer] a preparer covering every registered type
      def record_preparer
        @record_preparer ||= begin
          type_metadata = types.filter_map do |name, metadata|
            if (fields = metadata["fields"])
              fields_by_name = fields.transform_values do |field|
                Indexer::RecordPreparer::FieldMetadata.new(type: field.fetch("type"), name_in_index: field.fetch("name_in_index"))
              end
              Indexer::RecordPreparer::TypeMetadata.new(name: name, fields_by_name: fields_by_name)
            end
          end
          Indexer::RecordPreparer.new(@indexing_preparers, type_metadata)
        end
      end

      private

      # Lists are `repeated` fields; lists of lists nest wrapper messages inside the containing message.
      def field_type_for(message, field, overrides)
        list_depth = 0
        while field.label == :repeated
          list_depth += 1
          break unless field.type == :message
          wrapper = field.subtype # : ::Google::Protobuf::Descriptor
          break unless wrapper.name.start_with?("#{message.name}.")
          field = wrapper.lookup("values") # : ::Google::Protobuf::FieldDescriptor
        end

        "[" * list_depth + base_type_for(field, overrides) + "]" * list_depth
      end

      def base_type_for(field, overrides)
        if (type = overrides&.type)
          types[type] ||= {"scalar" => @metadata.types_by_name.fetch(type).scalar, "proto_type" => proto_type_of(field)}
          return type
        end

        subtype_name = proto_type_of(field)
        if subtype_name.start_with?("#{package_name}.")
          subtype = field.subtype # : untyped
          (field.type == :enum) ? register_enum(subtype) : register(subtype)
        else
          proto_type = proto_type_of(field)
          DEFAULT_SCALARS_BY_PROTO_TYPE.fetch(proto_type).tap do |scalar|
            types[scalar] ||= {"scalar" => scalar, "proto_type" => proto_type}
          end
        end
      end

      def register_enum(descriptor)
        name = descriptor.name.delete_prefix("#{package_name}.")
        types[name] ||= begin
          # Every value carries the prefix of the generated zero value, `<PREFIX>_UNSPECIFIED`.
          prefix = descriptor.lookup_value(0).to_s.delete_suffix("UNSPECIFIED")
          overrides = @metadata.types_by_name[name]&.non_standard_enum_values_by_name || {}
          values = descriptor.filter_map do |value_name, number|
            [value_name.to_s, overrides.fetch(value_name.to_s) { ProtoConversions.enum_value_to_eg_name(value_name.to_s, prefix.delete_suffix("_")) }] unless number == 0
          end
          {"enum_values" => values.to_h}
        end
        name
      end

      def proto_type_of(field)
        field.subtype&.name || field.type.to_s
      end
    end
  end
end
