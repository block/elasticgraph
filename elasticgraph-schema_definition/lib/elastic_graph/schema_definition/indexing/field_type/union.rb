# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/schema_definition/indexing/field_type/object"
require "elastic_graph/support/hash_util"

module ElasticGraph
  module SchemaDefinition
    module Indexing
      module FieldType
        # Responsible for the JSON schema and mapping of a {SchemaElements::UnionType}.
        #
        # @note In JSON schema, we model this with a `oneOf`, and a `__typename` field on each subtype.
        # @note Within the mapping, we have a single object type that has a set union of the properties
        #   of the subtypes (and also a `__typename` keyword field).
        #
        # @!attribute [r] subtypes_by_name
        #   @return [Hash<String, Object>] the subtypes of the union, keyed by name.
        #
        # @api private
        class Union < ::Data.define(:subtypes_by_name)
          # @return [Hash<String, ::Object>] the JSON schema for this union type.
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

          # @return [Hash<String, ::Object>] the datastore mapping for this union type.
          def to_mapping
            mapping_subfields = subtypes_by_name.values.map(&:subfields).reduce([], :union)

            Support::HashUtil.deep_merge(
              Field.normalized_mapping_hash_for(mapping_subfields),
              {"properties" => {"__typename" => {"type" => "keyword"}}}
            )
          end

          # @return [Hash<String, ::Object>] additional ElasticGraph metadata to put in the JSON schema for this union type.
          def json_schema_field_metadata_by_field_name
            {}
          end

          # @param customizations [Hash<String, ::Object>] JSON schema customizations
          # @return [Hash<String, ::Object>] formatted customizations.
          def format_field_json_schema_customizations(customizations)
            customizations
          end
        end
      end
    end
  end
end
