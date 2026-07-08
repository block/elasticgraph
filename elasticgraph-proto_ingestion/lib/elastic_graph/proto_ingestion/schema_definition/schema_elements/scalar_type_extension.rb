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

          # Validates that a protobuf type has been configured on this scalar type. GraphQL-only
          # scalar types are skipped because they are not part of ingestion.
          #
          # @return [void]
          # @raise [Errors::SchemaError] when missing
          def finalize_protobuf_configuration!
            return if graphql_only?
            proto_name
            nil
          end

          # Scalars map to protobuf field types and do not render standalone definitions.
          #
          # @return [nil]
          def to_proto(_schema, _package_name)
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
