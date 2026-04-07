# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "delegate"

module ElasticGraph
  module JSONIngestion
    module SchemaDefinition
      module FieldType
        # Wraps a union indexing field type to add JSON schema serialization.
        class Union < ::SimpleDelegator
          # @return [Hash] empty hash, as union types have no subfields
          def json_schema_field_metadata_by_field_name
            {}
          end

          # Returns the customizations as-is for union types.
          #
          # @param customizations [Hash<String, Object>] the customizations to format
          # @return [Hash<String, Object>] the formatted customizations
          def format_field_json_schema_customizations(customizations)
            customizations
          end

          # @return [Hash<String, Object>] the JSON schema definition for this union type
          def to_json_schema
            subtype_json_schemas = __getobj__.subtypes_by_name.keys.map { |name| {"$ref" => "#/$defs/#{name}"} }

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
