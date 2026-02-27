# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/errors"
require "elastic_graph/proto/schema_definition/factory_extension"

module ElasticGraph
  module Proto
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

        # Configures proto artifact generation behavior.
        #
        # @param package_name [String] proto package name to emit
        # @param replace_json_schemas [Boolean] when true, removes json schema artifacts and emits proto instead
        # @param field_number_mapping_file [String, nil] mapping artifact file name (relative to schema artifacts directory)
        # @param enforce_field_number_mapping [Boolean] when true, requires the mapping file to exist
        # @return [void]
        def proto_schema_artifacts(
          package_name: "elasticgraph",
          replace_json_schemas: false,
          field_number_mapping_file: nil,
          enforce_field_number_mapping: false
        )
          unless [true, false].include?(replace_json_schemas)
            raise Errors::SchemaError, "`replace_json_schemas` must be true or false"
          end

          unless [true, false].include?(enforce_field_number_mapping)
            raise Errors::SchemaError, "`enforce_field_number_mapping` must be true or false"
          end

          if field_number_mapping_file && !field_number_mapping_file.is_a?(String)
            raise Errors::SchemaError, "`field_number_mapping_file` must be a String when provided"
          end

          if enforce_field_number_mapping && field_number_mapping_file.nil? && (@proto_field_number_mappings || {}).empty?
            raise Errors::SchemaError, "Cannot enforce proto field-number mappings without configured mappings. " \
              "Provide `field_number_mapping_file:` or call `configure_proto_field_number_mappings`."
          end

          @proto_schema_package_name = package_name
          @replace_json_schema_artifacts_with_proto = replace_json_schemas
          @proto_field_number_mapping_file = field_number_mapping_file
          @enforce_proto_field_number_mappings = enforce_field_number_mapping
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
        # @param enforce [Boolean]
        # @return [void]
        def configure_proto_field_number_mappings(proto_field_number_mappings, enforce: false)
          unless [true, false].include?(enforce)
            raise Errors::SchemaError, "`enforce` must be true or false"
          end

          @proto_field_number_mappings = proto_field_number_mappings
          @enforce_proto_field_number_mappings = enforce
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
          @proto_field_number_mapping_file
        end

        # @private
        def proto_field_number_mappings
          @proto_field_number_mappings || {}
        end

        # @private
        def enforce_proto_field_number_mappings?
          @enforce_proto_field_number_mappings || false
        end

        # @private
        def replace_json_schema_artifacts_with_proto?
          @replace_json_schema_artifacts_with_proto || false
        end
      end
    end
  end
end
