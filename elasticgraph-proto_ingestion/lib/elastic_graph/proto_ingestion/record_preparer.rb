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
        @scalar_types_by_name = schema_artifacts.runtime_metadata.scalar_types_by_name
        @types = {}
        @enums = {}
        @mutex = ::Mutex.new
      end

      # Implements the indexer's record-preparer interface without an intermediate public record hash.
      # Does not mutate the native message or its nested values.
      def prepare_for_index(_type_name, message, mapping_properties)
        type = @mutex.synchronize { @types[message.class] ||= build_type(message.class.descriptor) }
        type.prepare(message, mapping_properties)
      end

      private

      # Resolved once per protobuf message class (together with all nested message types) so
      # preparation acquires `@mutex` once per root record and never re-inspects descriptors.
      Type = ::Data.define(:name, :fields) do
        # @implements Type

        def prepare(message, mapping_properties)
          prepared = {} # : ::Hash[::String, untyped]
          fields.each { |field| field.prepare_into(prepared, message, mapping_properties) }

          typename_type = mapping_properties&.dig("__typename", "type")
          if typename_type && typename_type != "constant_keyword"
            prepared["__typename"] = name
          end

          prepared
        end
      end

      # Prepares a message of a union or interface type by dispatching its `value` oneof
      # to the pre-resolved concrete `Type` for the active alternative.
      AbstractType = ::Data.define(:types_by_alternative) do
        # @implements AbstractType

        def prepare(message, mapping_properties)
          alternative = message.value
          return nil unless alternative

          types_by_alternative.fetch(alternative).prepare(message.public_send(alternative), mapping_properties)
        end
      end

      Field = ::Data.define(:name, :name_in_index, :presence_method, :list_depth, :leaf_preparer, :child_type) do
        # @implements Field

        # Adds this field's prepared value to `prepared`, unless `message` leaves this singular field unset.
        def prepare_into(prepared, message, mapping_properties)
          return if presence_method && !message.public_send(presence_method)

          nested_mapping = child_type ? mapping_properties&.dig(name_in_index, "properties") : nil
          prepared[name_in_index] = prepare_value(message[name], nested_mapping, list_depth)
        end

        private

        def prepare_value(value, nested_mapping, depth)
          if depth > 0
            return value.map do |item|
              prepare_value((depth > 1) ? item.values : item, nested_mapping, depth - 1)
            end
          end

          if (child = child_type)
            child.prepare(value, nested_mapping)
          else
            preparer = leaf_preparer # : ^(untyped) -> untyped
            preparer.call(value)
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

        name = type_name_for(descriptor)
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
          # Events with unknown enum numbers are rejected before preparation.
          leaf_preparer = ->(value) { enum_values.fetch(value) }
        when :message
          message_descriptor = leaf.subtype # : ::Google::Protobuf::Descriptor
          if message_descriptor.name.start_with?("#{@metadata.package_name}.")
            child_type = resolve_type(message_descriptor)
          else
            leaf_preparer = build_scalar_preparer(leaf, field_meta, message_descriptor: message_descriptor)
          end
        else
          leaf_preparer = build_scalar_preparer(leaf, field_meta)
        end

        Field.new(name, name_in_index, presence_method, list_depth, leaf_preparer, child_type)
      end

      def build_enum(descriptor)
        @enums[descriptor] ||= begin
          name = type_name_for(descriptor)
          overrides = @metadata.types_by_name[name]&.non_standard_enum_values_by_name || {}
          entries = descriptor.to_h
          prefix = entries.key(0).to_s.delete_suffix("_UNSPECIFIED")
          values = {} # : ::Hash[::Symbol | ::Integer, ::String?]

          entries.each do |symbol, number|
            key = symbol.to_s
            value = (number == 0) ? nil : (overrides[key] || ProtoConversions.enum_value_to_eg_name(key, prefix))
            # JRuby can expose repeated enum values as numbers rather than symbols.
            values[symbol] = values[number] = value
          end

          values
        end
      end

      def build_scalar_preparer(leaf_field, field_meta, message_descriptor: nil)
        if (type_name = field_meta&.type)
          scalar = @metadata.types_by_name.fetch(type_name).scalar
        end

        proto_type = message_descriptor ? message_descriptor.name : leaf_field.type.to_s
        type_name ||= DEFAULT_SCALARS_BY_PROTO_TYPE.fetch(proto_type)
        preparer = @scalar_types_by_name.fetch(type_name).load_indexing_preparer.extension_class # : singleton(SchemaArtifacts::RuntimeMetadata::ScalarIndexingPreparerInterface)

        if message_descriptor
          # Message scalars (such as `google.protobuf.Timestamp`) are prepared from their canonical protobuf JSON form.
          ->(value) { preparer.prepare_for_indexing(::JSON.parse(::Google::Protobuf.encode_json(value))) }
        elsif scalar == "Untyped"
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
