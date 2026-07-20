# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/errors"

module ElasticGraph
  module ProtoIngestion
    module SchemaDefinition
      module SchemaElements
        # Extends ScalarType with proto field type conversion.
        module ScalarTypeExtension
          # Default protobuf types applied to ElasticGraph's built-in scalar types as they are constructed.
          BUILT_IN_SCALAR_PROTO_TYPES_BY_NAME = {
            "Boolean" => "bool",
            "Cursor" => "string",
            "Date" => "string",
            "DateTime" => "string",
            "Float" => "double",
            "ID" => "string",
            "Int" => "int32",
            "JsonSafeLong" => "int64",
            "LocalTime" => "string",
            "LongString" => "int64",
            "String" => "string",
            "TimeZone" => "string",
            "Untyped" => "string"
          }.freeze

          # Configured protobuf type (e.g. string, int64, bool).
          # @dynamic protobuf_type
          attr_reader :protobuf_type

          # Configures the protobuf type for this scalar type.
          #
          # @param type [String] protobuf scalar type name
          # @return [void]
          def protobuf(type:)
            @protobuf_type = type
          end

          # Applies any built-in protobuf type, yields for further configuration, and validates the result.
          #
          # @yield additional scalar type configuration
          # @return [void]
          # @raise [Errors::SchemaError] when a protobuf type is missing
          def initialize_proto_extension
            original_name = type_ref.with_reverted_override.name
            if (proto_type = BUILT_IN_SCALAR_PROTO_TYPES_BY_NAME[original_name])
              protobuf type: proto_type
            end

            yield
            return if graphql_only?

            proto_name
            nil
          end

          # Scalars map to protobuf field types and do not render standalone definitions.
          #
          # @return [nil]
          def to_proto(_package_name)
            nil
          end

          # Returns the schema types referenced by this definition.
          #
          # @return [Array]
          def referenced_proto_types
            []
          end

          # Returns this scalar's name in protobuf schemas.
          #
          # @return [String]
          def proto_name
            protobuf_type || raise(Errors::SchemaError, "Protobuf type not configured for scalar type `#{name}`. " \
                'To proceed, call `protobuf type: "TYPE"` on the scalar type definition.')
          end

          # Returns this scalar's name when referenced by a protobuf field.
          #
          # @return [String]
          def proto_type_reference(_package_name)
            proto_name
          end
        end
      end
    end
  end
end
