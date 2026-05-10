# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/json_ingestion/schema_definition/indexing/field_reference"
require "elastic_graph/json_ingestion/schema_definition/json_schema_option_validator"

module ElasticGraph
  module JSONIngestion
    module SchemaDefinition
      # Namespace for schema-element extensions that contribute JSON schema generation and validation.
      module SchemaElements
        # Extends schema-definition fields with JSON schema validation behavior.
        module FieldExtension
          # @return [Hash<Symbol, Object>] JSON schema options for this field
          def json_schema_options
            @json_schema_options ||= {}
          end

          # @return [Boolean] whether this field has been marked as non-nullable in the JSON schema
          def non_nullable_in_json_schema
            @non_nullable_in_json_schema || false
          end

          # Sets whether this field is non-nullable in the JSON schema.
          # @param value [Boolean] true to make the field non-nullable
          attr_writer :non_nullable_in_json_schema

          # Configures JSON schema options for this field.
          #
          # @param nullable [Boolean, nil] set to `false` to make this field non-nullable in the JSON schema
          # @param options [Hash<Symbol, Object>] additional JSON schema options
          # @return [void]
          def json_schema(nullable: nil, **options)
            if options.key?(:type)
              raise Errors::SchemaError, "Cannot override JSON schema type of field `#{name}` with `#{options.fetch(:type)}`"
            end

            case nullable
            when true
              raise Errors::SchemaError, "`nullable: true` is not allowed on a field--just declare the GraphQL field as being nullable (no `!` suffix) instead."
            when false
              @non_nullable_in_json_schema = true
            end

            JSONSchemaOptionValidator.validate!(self, options)
            json_schema_options.update(options)
          end

          # @private
          def to_indexing_field_reference
            reference = super
            return nil unless reference

            type_for_json_schema = (non_nullable_in_json_schema ? type.wrap_non_null : type) # : ::ElasticGraph::SchemaDefinition::SchemaElements::TypeReference & TypeReferenceExtension

            Indexing::FieldReference.new(
              field_reference: reference.with(type: type_for_json_schema),
              json_schema_layers: type_for_json_schema.json_schema_layers,
              json_schema_customizations: json_schema_options
            )
          end
        end
      end
    end
  end
end
