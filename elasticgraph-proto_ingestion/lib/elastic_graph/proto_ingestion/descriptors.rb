# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/proto_ingestion"

module ElasticGraph
  module ProtoIngestion
    # Shared helpers for inspecting `Google::Protobuf` descriptors against ElasticGraph runtime metadata.
    # @private
    module Descriptors
      # Unwrapped metadata extracted from a protobuf field descriptor.
      # @private
      UnwrappedField = ::Data.define(:name, :presence_method, :list_depth, :leaf)

      def self.type_name(descriptor, metadata)
        descriptor.name.delete_prefix("#{metadata.package_name}.")
      end

      def self.internal_message?(descriptor, metadata)
        descriptor.name.start_with?("#{metadata.package_name}.")
      end

      def self.abstract?(descriptor)
        !descriptor.lookup_oneof("value").nil?
      end

      def self.unwrap_abstract(message)
        alternative = message.value
        return nil unless alternative

        message.public_send(alternative)
      end

      def self.unwrap_field(descriptor, field)
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

        UnwrappedField.new(name: name, presence_method: presence_method, list_depth: list_depth, leaf: leaf)
      end

      def self.scalar_info(leaf_field, field_meta, metadata)
        message_descriptor = if leaf_field.type == :message
          leaf_field.subtype # : ::Google::Protobuf::Descriptor
        end
        if (type_name = field_meta&.type)
          scalar = metadata.types_by_name.fetch(type_name).scalar
        end

        proto_type = message_descriptor ? message_descriptor.name : leaf_field.type.to_s
        type_name ||= DEFAULT_SCALARS_BY_PROTO_TYPE.fetch(proto_type)
        scalar ||= type_name
        [type_name, scalar]
      end
    end
  end
end
