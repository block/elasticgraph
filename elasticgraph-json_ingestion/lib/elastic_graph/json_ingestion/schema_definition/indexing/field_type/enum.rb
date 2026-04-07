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
      module Indexing
        # Contains JSON-schema-aware wrappers around core indexing field types.
        module FieldType
          # Wraps an enum indexing field type to add JSON schema serialization.
          #
          # We use a wrapper here rather than `extend` because the core enum field type is a frozen `Data` object.
          class Enum < ::SimpleDelegator
            # Enums have no subfields, so there is no additional ElasticGraph metadata to contribute.
            #
            # @return [Hash<String, ::Object>] additional ElasticGraph metadata to put in the JSON schema for this enum type.
            def json_schema_field_metadata_by_field_name
              {}
            end

            # Enum field customizations are limited to the `enum` keyword. The field type itself already provides
            # the JSON schema `type`, and object-style keywords such as `properties` do not apply to enum values.
            #
            # @param customizations [Hash<String, ::Object>] the customizations to format
            # @return [Hash<String, ::Object>] the filtered customizations
            def format_field_json_schema_customizations(customizations)
              customizations.slice("enum")
            end

            # @return [Hash<String, ::Object>] the JSON schema definition for this enum type
            def to_json_schema
              {"type" => "string", "enum" => __getobj__.enum_value_names}
            end
          end
        end
      end
    end
  end
end
