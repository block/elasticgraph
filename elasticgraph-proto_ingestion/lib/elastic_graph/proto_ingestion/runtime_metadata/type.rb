# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/proto_ingestion/runtime_metadata/field"

module ElasticGraph
  module ProtoIngestion
    module RuntimeMetadata
      # Ingestion facts for a scalar, enum, or message type.
      #
      # @private
      Type = ::Data.define(:fields_by_name, :enum_values_by_name, :enum_zero_value, :scalar, :subtypes_by_field_name) do
        # @implements Type

        def initialize(fields_by_name: {}, enum_values_by_name: {}, enum_zero_value: nil, scalar: nil, subtypes_by_field_name: {})
          super
        end

        def self.from_hash(hash)
          fields = hash["fields_by_name"] || {} # : ::Hash[::String, untyped]
          enum_values = hash["enum_values_by_name"] || {} # : ::Hash[::String, ::String]
          new(
            fields_by_name: fields.transform_values { |field| Field.from_hash(field) },
            enum_values_by_name: enum_values,
            enum_zero_value: hash["enum_zero_value"],
            scalar: hash["scalar"],
            subtypes_by_field_name: hash["subtypes_by_field_name"] || {}
          )
        end

        def to_dumpable_hash
          {
            "fields_by_name" => fields_by_name.sort.to_h.transform_values(&:to_dumpable_hash),
            "enum_values_by_name" => enum_values_by_name,
            "enum_zero_value" => enum_zero_value,
            "scalar" => scalar,
            "subtypes_by_field_name" => subtypes_by_field_name
          }
        end
      end
    end
  end
end
