# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  module JSONIngestion
    module SchemaDefinition
      module Indexing
        module FieldType
          # Extends union indexing field types with JSON schema serialization.
          #
          # @private
          module UnionExtension
            # @return [Hash] empty hash, as union types have no subfields
            def json_schema_field_metadata_by_field_name
              {}
            end

            # @param customizations [Hash<String, Object>] the customizations to format
            # @return [Hash<String, Object>] the formatted customizations
            def format_field_json_schema_customizations(customizations)
              customizations
            end

            # @return [Hash<String, Object>] the JSON schema definition for this union type
            def to_json_schema
              subtype_json_schemas = subtypes_by_name.keys.map { |name| {"$ref" => "#/$defs/#{name}"} }

              # A union type can represent multiple subtypes, referenced by the "anyOf" clause below.
              # We also add a requirement for the presence of __typename to indicate which type
              # is being referenced (this property is pre-defined on the type itself as a constant).
              #
              # Note: Although both "oneOf" and "anyOf" keywords are valid for combining schemas
              # to form a union, and validate equivalently when no object can satisfy multiple of the
              # subschemas (which is the case here given the __typename requirements are mutually
              # exclusive), we chose to use "oneOf" here because it works better with this library:
              # https://github.com/pwall567/json-kotlin-schema-codegen
              {
                "required" => %w[__typename],
                "oneOf" => subtype_json_schemas
              }
            end
          end
        end
      end
    end
  end
end
