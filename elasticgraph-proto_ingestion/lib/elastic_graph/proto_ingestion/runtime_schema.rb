# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/errors"
require "elastic_graph/indexer/record_preparer"

module ElasticGraph
  module ProtoIngestion
    # Describes indexed protobuf records. Structure comes from the protobuf descriptors of the
    # messages being ingested; runtime metadata supplies only what those descriptors cannot express:
    # private index field names, scalars with ingestion rules beyond their wire type, enum value names
    # that casing cannot recover, and the valid time zones when a `TimeZone` field needs them.
    # @private
    class RuntimeSchema
      # The scalar a field is ingested as when runtime metadata does not name one.
      DEFAULT_SCALARS_BY_PROTO_TYPE = {
        "bool" => "Boolean",
        "double" => "Float",
        "google.protobuf.Timestamp" => "DateTime",
        "int32" => "Int",
        "int64" => "LongString",
        "string" => "String"
      }.freeze

      # @dynamic types, package_name, time_zones, reserved_envelope_fields
      attr_reader :types, :package_name, :time_zones, :reserved_envelope_fields

      def initialize(schema_artifacts)
        extension = schema_artifacts.runtime_metadata.indexer_extension_modules.find do |candidate|
          candidate.extension_ref.fetch("name") == "ElasticGraph::ProtoIngestion::IndexerExtension"
        end
        unless extension
          raise Errors::ConfigError, "Protobuf runtime metadata is missing. Enable ProtoIngestion::SchemaDefinition::APIExtension and dump schema artifacts."
        end
        config = extension.extension_ref.fetch("config")
        @package_name = config.fetch("package_name")
        @public_names = config["types"] || {} # : ::Hash[::String, ::String]
        @proto_names = @public_names.invert.merge(config["type_aliases"] || {}) # : ::Hash[::String, ::String]
        @deleted_types = (config["deleted_types"] || []).to_set # : ::Set[::String]
        @reserved_envelope_fields = config["reserved_envelope_fields"] || {} # : ::Hash[::String, ::String]
        @retired_enum_values = config["retired_enum_values"] || {} # : ::Hash[::String, ::Array[::Integer]]
        @field_overrides = config["fields"] || {} # : ::Hash[::String, ::Hash[::String, ::Hash[::String, ::String]]]
        @enum_value_overrides = config["enum_values"] || {} # : ::Hash[::String, ::Hash[::String, ::String]]
        @time_zones = config["time_zones"] || [] # : ::Array[::String]
        @indexing_preparers = schema_artifacts.runtime_metadata.scalar_types_by_name.transform_values do |scalar|
          scalar.load_indexing_preparer.extension_class
        end
        # Filled in from descriptors as messages arrive; shared with the converter and validator.
        @types = {}
      end

      # @return [String] the current public name for a protobuf type
      def public_type_name_for(proto_name)
        @public_names.fetch(proto_name, proto_name)
      end

      # @return [String] the stable protobuf name for a current or historical public type
      def proto_type_name_for(public_name)
        @proto_names.fetch(public_name, public_name)
      end

      # @return [Boolean] whether a raw message's type has been explicitly deleted
      def deleted_type?(name)
        @deleted_types.include?(name) || @deleted_types.include?(proto_type_name_for(name))
      end

      # Adds a message type, and every type it references, to {#types}.
      # @param descriptor [Google::Protobuf::Descriptor]
      # @return [String] the type's name
      def register(descriptor)
        proto_name = descriptor.name.delete_prefix("#{package_name}.")
        name = public_type_name_for(proto_name)
        return name if types.key?(name)

        # Register before following references, since protobuf messages may be recursive.
        types[name] = {}
        if (oneof = descriptor.lookup_oneof("value"))
          types[name] = {"subtypes" => oneof.map { |field| register(field.subtype) }}
        else
          overrides = @field_overrides[proto_name] || {} # : ::Hash[::String, ::Hash[::String, ::String]]
          fields = descriptor.to_h do |entry|
            # Message descriptors yield only fields; oneofs are reached through `lookup_oneof`.
            field = entry # : ::Google::Protobuf::FieldDescriptor
            field_overrides = overrides[field.name] || {} # : ::Hash[::String, ::String]
            public_name = field_overrides.fetch("public_name", field.name)
            [public_name, {
              "type" => field_type_for(descriptor, field, field_overrides),
              "proto_name" => field.name,
              "name_in_index" => field_overrides.fetch("name_in_index", public_name)
            }]
          end
          types[name] = {"fields" => fields}
          @record_preparer = nil
        end

        name
      end

      # @return [ElasticGraph::Indexer::RecordPreparer] a preparer covering every registered type
      def record_preparer
        @record_preparer ||= ::ElasticGraph::Indexer::RecordPreparer.new(@indexing_preparers, types.filter_map do |name, metadata|
          if (fields = metadata["fields"])
            ::ElasticGraph::Indexer::RecordPreparer::TypeMetadata.new(name: name, fields_by_name: fields.transform_values do |field|
              ::ElasticGraph::Indexer::RecordPreparer::FieldMetadata.new(type: field.fetch("type"), name_in_index: field.fetch("name_in_index"))
            end)
          end
        end)
      end

      private

      # Lists are `repeated` fields; lists of lists nest wrapper messages inside the containing message.
      def field_type_for(message, field, overrides)
        list_depth = 0
        while field.repeated?
          list_depth += 1
          break unless field.type == :message
          wrapper = field.subtype # : ::Google::Protobuf::Descriptor
          break unless wrapper.name.start_with?("#{message.name}.")
          field = wrapper.lookup("values") # : ::Google::Protobuf::FieldDescriptor
        end

        "[" * list_depth + base_type_for(field, overrides) + "]" * list_depth
      end

      def base_type_for(field, overrides)
        if (type = overrides["type"])
          types[type] ||= {"scalar" => overrides.fetch("scalar", type), "proto_type" => proto_type_of(field)}
          return type
        end

        subtype_name = field.submsg_name.to_s
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
        proto_name = descriptor.name.delete_prefix("#{package_name}.")
        name = public_type_name_for(proto_name)
        types[name] ||= begin
          # Every value carries the prefix of the generated zero value, `<PREFIX>_UNSPECIFIED`.
          prefix = descriptor.lookup_value(0).to_s.delete_suffix("UNSPECIFIED")
          overrides = @enum_value_overrides[proto_name] || {} # : ::Hash[::String, ::String]
          values = descriptor.filter_map do |value_name, number|
            [value_name.to_s, overrides.fetch(value_name.to_s) { value_name.to_s.delete_prefix(prefix) }] unless number == 0
          end
          {"enum_values" => values.to_h, "retired_enum_values" => @retired_enum_values.fetch(proto_name, [])}
        end
        name
      end

      def proto_type_of(field)
        field.submsg_name || field.type.to_s
      end
    end
  end
end
