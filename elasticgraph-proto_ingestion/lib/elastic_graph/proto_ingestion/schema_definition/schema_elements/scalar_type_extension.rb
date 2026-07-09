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
          # Default protobuf options applied to ElasticGraph's built-in scalar types as they are constructed.
          BUILT_IN_SCALAR_PROTO_OPTIONS_BY_NAME = {
            "Boolean" => {type: "bool"},
            "Cursor" => {type: "string"},
            "Date" => {type: "string", comment: %(ISO 8601 date, e.g. "2024-11-25")},
            "DateTime" => {type: "google.protobuf.Timestamp", import: "google/protobuf/timestamp.proto"},
            "Float" => {type: "double"},
            "ID" => {type: "string"},
            "Int" => {type: "int32"},
            "JsonSafeLong" => {type: "int64"},
            "LocalTime" => {type: "string", comment: %(ISO 8601 local time, e.g. "14:23:12")},
            "LongString" => {type: "int64"},
            "String" => {type: "string"},
            "TimeZone" => {type: "string", comment: %(IANA time zone identifier, e.g. "America/Los_Angeles")},
            "Untyped" => {type: "string"}
          }.freeze # : ::Hash[::String, {type: ::String, ?import: ::String, ?comment: ::String}]

          # An `import` is rendered as `import "PATH";`, so a quote or newline in the path would
          # produce invalid proto. `protoc` also requires the path to name a `.proto` file.
          VALID_PROTOBUF_IMPORT_PATH = %r{\A[\w./-]+\.proto\z}

          # Configured protobuf type (e.g. string, int64, bool).
          # @dynamic protobuf_type
          attr_reader :protobuf_type

          # Proto file to import for the configured protobuf type, if it is externally defined.
          # @dynamic protobuf_import
          attr_reader :protobuf_import

          # Comment rendered on generated proto fields of this scalar type.
          # @dynamic protobuf_comment
          attr_reader :protobuf_comment

          # Configures the protobuf type for this scalar type.
          #
          # @param type [String] protobuf type name
          # @param import [String, nil] proto file to import for an externally defined type
          # @param comment [String, nil] single-line comment rendered on generated fields of this type
          # @return [void]
          # @raise [Errors::SchemaError] when `import` is not a `.proto` file path
          # @raise [Errors::SchemaError] when `comment` spans multiple lines
          def protobuf(type:, import: nil, comment: nil)
            if import && !VALID_PROTOBUF_IMPORT_PATH.match?(import)
              raise Errors::SchemaError, "`protobuf` import for `#{name}` must be the path of a `.proto` file, " \
                "but got: #{import.inspect}."
            end

            # The comment is rendered as a trailing `// ...` on the field line, so a newline would
            # push the remainder onto its own line as bare, invalid proto syntax. Multi-line prose
            # belongs on the field's GraphQL doc comment, which renders as `//` lines above the field.
            if comment&.include?("\n")
              raise Errors::SchemaError, "`protobuf` comment for `#{name}` must be a single line, but got: #{comment.inspect}. " \
                "Use the field's doc comment for multi-line documentation."
            end

            @protobuf_type = type
            @protobuf_import = import
            @protobuf_comment = comment
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
        end
      end
    end
  end
end
