# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  module SchemaDefinition
    module Indexing
      # Contains implementation logic for the different types of indexing fields.
      #
      # @api private
      module FieldType
        # @!parse class Enum < ::Data; end
        Enum = ::Data.define(:enum_value_names)

        # Responsible for the JSON schema and mapping of a {SchemaElements::EnumType}.
        #
        # @!attribute [r] enum_value_names
        #   @return [Array<String>] list of names of values in this enum type.
        #
        # @api private
        class Enum < ::Data
          # @return [Hash<String, ::Object>] the JSON schema for this enum type.
          def to_json_schema
            {"type" => "string", "enum" => enum_value_names}
          end

          # @return [Hash<String, ::Object>] the datastore mapping for this enum type.
          def to_mapping
            {"type" => "keyword"}
          end

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

          # @dynamic initialize, enum_value_names
        end
      end
    end
  end
end
