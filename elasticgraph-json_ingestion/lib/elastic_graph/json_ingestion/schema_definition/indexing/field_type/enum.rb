# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "delegate"
require "elastic_graph/schema_definition/indexing/field_type/enum"

module ElasticGraph
  module JSONIngestion
    module SchemaDefinition
      module Indexing
        # Namespace for JSON-schema-aware indexing field types.
        module FieldType
          # Wraps enum indexing field types with JSON schema serialization.
          #
          # @private
          class Enum < DelegateClass(ElasticGraph::SchemaDefinition::Indexing::FieldType::Enum)
            # @return [Hash<String, ::Object>] additional ElasticGraph metadata to put in the JSON schema for this enum type.
            def json_schema_field_metadata_by_field_name
              {}
            end

            # @param customizations [Hash<String, ::Object>] JSON schema customizations
            # @return [Hash<String, ::Object>] formatted customizations.
            def format_field_json_schema_customizations(customizations)
              # Since an enum type already restricts the values to a small set of allowed values, we do not need to keep
              # other customizations (such as the `maxLength` field customization EG automatically applies to fields
              # indexed as a `keyword`--we don't allow enum values to exceed that length, anyway).
              #
              # It's desirable to restrict what customizations are applied because when a publisher uses the JSON schema
              # to generate code using a library such as https://github.com/pwall567/json-kotlin-schema-codegen, we found
              # that the presence of extra field customizations inhibits the library's ability to generate code in the way
              # we want (it causes the type of the enum to change since the JSON schema changes from a direct `$ref` to
              # being wrapped in an `allOf`).
              #
              # However, we still want to apply `enum` customizations--this allows a user to "narrow" the set of allowed
              # values for a field. For example, a `Currency` enum could contain every currency, and a user may want to
              # restrict a specific `currency` field to a subset of currencies (e.g. to just USD, CAD, and EUR).
              customizations.slice("enum")
            end

            # @return [Hash<String, ::Object>] the JSON schema for this enum type.
            def to_json_schema
              {"type" => "string", "enum" => enum_value_names}
            end
          end
        end
      end
    end
  end
end
