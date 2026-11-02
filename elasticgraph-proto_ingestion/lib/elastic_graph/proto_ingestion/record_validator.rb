# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "date"
require "elastic_graph/constants"
require "elastic_graph/proto_ingestion"
require "elastic_graph/proto_ingestion/runtime_metadata/schema"
require "elastic_graph/support/valid_time_zones"
require "json"

module ElasticGraph
  module ProtoIngestion
    # Checks ElasticGraph constraints which the protobuf wire format cannot express.
    # Protobuf decoding already checks primitive wire types; this walk checks enum membership
    # and the narrower ranges/formats of ElasticGraph's built-in scalars. Generated fields are
    # optional to keep accepting historical publishers, so GraphQL nullability is not checked.
    # @private
    class RecordValidator
      TIMESTAMP_SECONDS_RANGE = (-62_135_596_800..253_402_300_799)
      TIMESTAMP_NANOS_RANGE = (0..999_999_999)
      WIRE_CONTRACT_SCALARS = %w[JsonSafeLong].to_set.freeze

      def self.valid_date?(value)
        /\A\d{4}-\d{2}-\d{2}\z/.match?(value) &&
          Date.valid_date?(value[0, 4].to_i, value[5, 2].to_i, value[8, 2].to_i)
      end

      def self.valid_timestamp?(value)
        TIMESTAMP_SECONDS_RANGE.cover?(value.seconds) && TIMESTAMP_NANOS_RANGE.cover?(value.nanos)
      end

      def self.valid_json?(value)
        JSON.parse(value)
        true
      rescue JSON::ParserError
        false
      end

      # Checks for scalars whose valid values are narrower than their protobuf wire type allows.
      SCALAR_CHECKS = {
        "JsonSafeLong" => ->(value) { (JSON_SAFE_LONG_MIN..JSON_SAFE_LONG_MAX).cover?(value) },
        "Float" => ->(value) { value.finite? },
        "Date" => ->(value) { valid_date?(value) },
        "DateTime" => ->(value) { valid_timestamp?(value) },
        "LocalTime" => ->(value) { VALID_LOCAL_TIME_REGEX.match?(value) },
        "TimeZone" => ->(value) { Support::VALID_TIME_ZONES.include?(value) },
        "Untyped" => ->(value) { valid_json?(value) }
      }.freeze # : Hash[String, ^(untyped) -> boolish]

      def initialize(metadata)
        @metadata = metadata
        @types = {}
        @mutex = Mutex.new
      end

      # Wire-critical numeric ranges and unknown enum values are never sampled out.
      def error_for(message, path = "record", wire_contract_only: false)
        type = @mutex.synchronize { @types[message.class] ||= build_type(message.class.descriptor) }
        fields = type.fields
        unless fields
          alternative = message.value
          return nil unless alternative
          return error_for(message.public_send(alternative), path, wire_contract_only: wire_contract_only)
        end

        fields.each do |field|
          next if wire_contract_only && !field.wire_contract
          next if field.presence_method && !message.public_send(field.presence_method)
          if (error = validate_value(field, message[field.name], field.list_depth, "#{path}.#{field.name}", wire_contract_only))
            return error
          end
        end
        nil
      end

      private

      Type = ::Data.define(:fields)
      Field = ::Data.define(:name, :presence_method, :list_depth, :nested_message, :wire_contract, :error_suffix, :leaf_check)

      def validate_value(field, value, depth, path, wire_contract_only)
        if depth > 0
          value.each_with_index do |item, index|
            nested = (depth > 1) ? item.values : item
            if (error = validate_value(field, nested, depth - 1, "#{path}[#{index}]", wire_contract_only))
              return error
            end
          end
          return nil
        end
        return error_for(value, path, wire_contract_only: wire_contract_only) if field.nested_message
        "#{path} #{field.error_suffix}" unless (_ = field.leaf_check).call(value)
      end

      def build_type(descriptor)
        name = type_name_for(descriptor)
        return Type.new(nil) if descriptor.lookup_oneof("value")

        overrides = @metadata.types_by_name[name]&.fields_by_name || {}
        fields = descriptor.filter_map do |entry|
          field = entry # : ::Google::Protobuf::FieldDescriptor
          build_field(descriptor, field, overrides[field.name])
        end
        Type.new(fields)
      end

      def build_field(descriptor, field, field_meta)
        name = field.name
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
          valid_symbols = enum_descriptor.to_h.keys.to_set
          Field.new(name, presence_method, list_depth, false, true, "has an unknown enum value.", ->(value) { valid_symbols.include?(value) })
        elsif leaf.type == :message && (_ = leaf.subtype).name.start_with?("#{@metadata.package_name}.")
          Field.new(name, presence_method, list_depth, true, true, nil, nil)
        else
          build_scalar_field(name, presence_method, list_depth, leaf, field_meta)
        end
      end

      def build_scalar_field(name, presence_method, list_depth, leaf_field, field_meta)
        if (type_name = field_meta&.type)
          scalar = @metadata.types_by_name.fetch(type_name).scalar # : String
        else
          proto_type = leaf_field.subtype&.name || leaf_field.type.to_s
          scalar = DEFAULT_SCALARS_BY_PROTO_TYPE.fetch(proto_type)
          type_name = scalar
        end
        return nil unless (check = SCALAR_CHECKS[scalar])

        Field.new(
          name,
          presence_method,
          list_depth,
          false,
          WIRE_CONTRACT_SCALARS.include?(scalar),
          "is not a valid #{type_name}.",
          check
        )
      end

      def type_name_for(descriptor)
        descriptor.name.delete_prefix("#{@metadata.package_name}.")
      end
    end
  end
end
