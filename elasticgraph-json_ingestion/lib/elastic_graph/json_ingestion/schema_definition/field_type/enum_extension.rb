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
        # Wraps an enum indexing field type to add JSON schema serialization.
        class Enum < ::SimpleDelegator
          # @return [Hash] empty hash, as enum types have no subfields
          def json_schema_field_metadata_by_field_name
            {}
          end

          # Filters customizations to only include `enum` for enum types.
          #
          # @param customizations [Hash<String, Object>] the customizations to format
          # @return [Hash<String, Object>] the filtered customizations
          def format_field_json_schema_customizations(customizations)
            customizations.slice("enum")
          end

          # @return [Hash<String, Object>] the JSON schema definition for this enum type
          def to_json_schema
            {"type" => "string", "enum" => __getobj__.enum_value_names}
          end
        end
      end
    end
  end
end
