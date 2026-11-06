# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/errors"
require "elastic_graph/proto_ingestion"
require "elastic_graph/proto_ingestion/runtime_metadata/type"

module ElasticGraph
  module ProtoIngestion
    module SchemaDefinition
      module SchemaElements
        # Extends ScalarType with proto field type conversion.
        module ScalarTypeExtension
          # An `import` is rendered as `import "PATH";`, so a quote or newline in the path would
          # produce invalid proto. `protoc` also requires the path to name a `.proto` file.
          VALID_PROTOBUF_IMPORT_PATH = %r{\A[\w./-]+\.proto\z}

          # Configured protobuf type (e.g. string, int64, bool).
          # @dynamic protobuf_type
          attr_reader :protobuf_type

          # Proto file to import for the configured protobuf type, if it is externally defined.
          # @dynamic protobuf_import
          attr_reader :protobuf_import

          # Comment rendered above each generated proto field of this scalar type.
          # @dynamic protobuf_field_comment
          attr_reader :protobuf_field_comment

          # Configures the protobuf type for this scalar type. Each call replaces the full protobuf
          # configuration, so an override that omits `import:` or `field_comment:` clears the value
          # configured by a prior call.
          #
          # @param type [String] protobuf type name
          # @param import [String, nil] proto file to import for an externally defined type
          # @param field_comment [String, nil] comment rendered above each generated field of this type
          # @return [void]
          # @raise [Errors::SchemaError] when `import` is not a `.proto` file path
          def protobuf(type:, import: nil, field_comment: nil)
            if import && !VALID_PROTOBUF_IMPORT_PATH.match?(import)
              raise Errors::SchemaError, "`protobuf` import for `#{name}` must be the path of a `.proto` file, " \
                "but got: #{import.inspect}."
            end

            @protobuf_type = type
            @protobuf_import = import
            @protobuf_field_comment = field_comment
          end

          # Applies any built-in protobuf type, yields for further configuration, and validates the result.
          #
          # @yield additional scalar type configuration
          # @return [void]
          # @raise [Errors::SchemaError] when a protobuf type is missing
          def initialize_proto_extension
            original_name = type_ref.with_reverted_override.name
            if (proto_options = BUILT_IN_SCALAR_PROTO_OPTIONS_BY_NAME[original_name])
              protobuf(**proto_options)
            end

            yield
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

          # Returns the scalar's original name when it differs from the default for its protobuf type.
          #
          # @return [RuntimeMetadata::Type]
          def proto_ingestion_metadata
            default_scalar = DEFAULT_SCALARS_BY_PROTO_TYPE[proto_name]
            scalar_name = type_ref.with_reverted_override.name

            RuntimeMetadata::Type.new(
              fields_by_name: {},
              non_standard_enum_values_by_name: {},
              scalar: (scalar_name == default_scalar) ? nil : scalar_name
            )
          end
        end
      end
    end
  end
end
