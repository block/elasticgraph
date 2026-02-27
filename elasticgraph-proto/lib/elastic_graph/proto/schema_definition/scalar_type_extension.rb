# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/errors"

module ElasticGraph
  module Proto
    module SchemaDefinition
      # Extends ScalarType with proto field type conversion.
      module ScalarTypeExtension
        # Fallback mapping from JSON schema scalar types to protobuf scalar field types.
        #
        # @return [Hash<String, String>]
        PROTO_FIELD_TYPE_BY_JSON_SCHEMA_TYPE = {
          "boolean" => "bool",
          "integer" => "int64",
          "number" => "double",
          "string" => "string"
        }.freeze

        # Configured proto field type (e.g. string, int64, bool).
        # @dynamic proto_field_type
        attr_reader :proto_field_type

        # Configures the proto field type for this scalar type.
        #
        # @param type [String] protobuf scalar type name
        # @return [void]
        def proto_field(type:)
          @proto_field_type = type
        end

        # Returns this scalar's proto field type.
        #
        # @return [String]
        # @raise [Errors::SchemaError] when missing
        def to_proto_field_type
          proto_field_type ||
            infer_proto_field_type_from_json_schema ||
            raise(Errors::SchemaError, "Proto field type not configured for scalar type `#{name}`. " \
              'To proceed, call `proto_field type: "TYPE"` on the scalar type definition.')
        end

        private

        def infer_proto_field_type_from_json_schema
          return nil unless respond_to?(:json_schema_options)

          types =
            case (type = json_schema_options[:type])
            when String, Symbol
              [type.to_s]
            when Array
              type.filter_map do |entry|
                (entry.is_a?(String) || entry.is_a?(Symbol)) ? entry.to_s : nil
              end
            else
              []
            end

          normalized_types = (types - ["null"]).uniq
          return nil unless normalized_types.size == 1

          PROTO_FIELD_TYPE_BY_JSON_SCHEMA_TYPE[normalized_types.first]
        end
      end
    end
  end
end
