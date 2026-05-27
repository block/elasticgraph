# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/errors"
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
          def non_nullable_in_json_schema?
            @non_nullable_in_json_schema || false
          end

          # Sets whether this field is non-nullable in the JSON schema.
          # @param value [Boolean] true to make the field non-nullable
          attr_writer :non_nullable_in_json_schema

          # Defines JSON Schema validations for this field. Validations defined here will be included in the
          # generated `json_schemas.yaml` artifact, which ElasticGraph uses to validate events before indexing.
          # Publishers may also use the artifact for code generation and validation before publishing events.
          #
          # Can be called multiple times; each call merges options into the existing set.
          #
          # Use these validations sparingly. Events that violate JSON Schema validation fail to index, so we
          # recommend limiting them to constraints that ElasticGraph needs in order to operate correctly.
          # `nullable: false` is also supported to disallow `null` values in indexed data while keeping the
          # GraphQL field nullable.
          #
          # @param nullable [Boolean, nil] set to `false` to make this field non-nullable in the JSON schema
          # @param options [Hash<Symbol, Object>] additional JSON schema options
          # @return [void]
          #
          # @example Define additional validations on a field
          #   ElasticGraph.define_schema do |schema|
          #     schema.object_type "Card" do |t|
          #       t.field "id", "ID!"
          #       t.field "expYear", "Int" do |f|
          #         f.json_schema minimum: 2000, maximum: 2099
          #       end
          #
          #       t.index "cards"
          #     end
          #   end
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

            Indexing::FieldReference.new(
              reference.with(type: type_for_json_schema),
              json_schema_layers: type_for_json_schema.json_schema_layers,
              json_schema_customizations: json_schema_options
            )
          end

          private

          def type_for_json_schema
            (non_nullable_in_json_schema? ? type.wrap_non_null : type).then do |type_ref|
              type_ref # : ElasticGraph::SchemaDefinition::SchemaElements::TypeReference & TypeReferenceExtension
            end
          end
        end
      end
    end
  end
end
