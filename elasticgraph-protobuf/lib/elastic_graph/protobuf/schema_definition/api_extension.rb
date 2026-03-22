# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/errors"
require "elastic_graph/protobuf"
require "elastic_graph/protobuf/schema_definition/factory_extension"

module ElasticGraph
  module Protobuf
    module SchemaDefinition
      # Module designed to be extended onto an API instance to enable proto artifact generation.
      module APIExtension
        # Maps built-in ElasticGraph scalar types to proto field types.
        PROTO_TYPES_BY_BUILT_IN_SCALAR_TYPE = {
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

        def self.extended(api)
          api.factory.extend FactoryExtension

          api.proto_schema_artifacts

          api.on_built_in_types do |type|
            if type.is_a?(ScalarTypeExtension)
              type.proto_field type: PROTO_TYPES_BY_BUILT_IN_SCALAR_TYPE.fetch(type.name)
            end
          end
        end

        # Configures protobuf artifact generation behavior.
        #
        # @param package_name [String] proto package name to emit
        # @return [void]
        def proto_schema_artifacts(package_name: "elasticgraph")
          if !package_name.is_a?(String) || package_name.empty?
            raise Errors::SchemaError, "`package_name` must be a non-empty String"
          end

          @proto_schema_package_name = package_name
          nil
        end

        # Registers mappings from GraphQL enum names to protobuf enum classes and transform options.
        # This is intended to support reusing enum mappings already maintained by applications
        # (for example in schema/proto consistency tests).
        #
        # @param proto_enums_by_graphql_enum [Hash]
        # @return [void]
        def proto_enum_mappings(proto_enums_by_graphql_enum)
          @proto_enums_by_graphql_enum = proto_enums_by_graphql_enum
          nil
        end

        # Configures proto field-number mappings directly from a hash.
        # Useful for tests and advanced use cases where mappings are sourced outside artifacts.
        #
        # @param proto_field_number_mappings [Hash]
        # @param enforce [Boolean] ignored; retained for compatibility with earlier prototypes and tests
        # @return [void]
        def configure_proto_field_number_mappings(proto_field_number_mappings, enforce: false)
          unless [true, false].include?(enforce)
            raise Errors::SchemaError, "`enforce` must be true or false"
          end

          @proto_field_number_mappings = proto_field_number_mappings
          nil
        end

        # @private
        def proto_schema_package_name
          @proto_schema_package_name || "elasticgraph"
        end

        # @private
        def proto_enums_by_graphql_enum
          @proto_enums_by_graphql_enum || {}
        end

        # @private
        def proto_field_number_mapping_file
          Protobuf::PROTO_FIELD_NUMBERS_FILE
        end

        # @private
        def proto_field_number_mappings
          @proto_field_number_mappings || {}
        end
      end
    end
  end
end
