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
      Type = ::Data.define(:fields_by_name, :enum_values_by_name, :scalar) do
        # @implements Type

        def initialize(fields_by_name: {}, enum_values_by_name: {}, scalar: nil)
          super
        end

        def self.from_hash(hash)
          fields = hash["fields_by_name"] || {} # : ::Hash[::String, untyped]
          enum_values = hash["enum_values_by_name"] || {} # : ::Hash[::String, ::String]
          new(
            fields_by_name: fields.transform_values { |field| Field.from_hash(field) },
            enum_values_by_name: enum_values,
            scalar: hash["scalar"]
          )
        end

        def to_dumpable_hash
          {
            "enum_values_by_name" => enum_values_by_name,
            "fields_by_name" => fields_by_name.sort.to_h.transform_values(&:to_dumpable_hash),
            "scalar" => scalar
          }.reject { |_, value| value.nil? || value == {} }
        end

        def empty?
          fields_by_name.empty? && enum_values_by_name.empty? && scalar.nil?
        end
      end
    end
  end
end
