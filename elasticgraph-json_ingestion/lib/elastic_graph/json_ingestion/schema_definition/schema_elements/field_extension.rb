# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/json_ingestion/schema_definition/indexing/field_reference"
require "elastic_graph/json_ingestion/schema_definition/json_schema_layers"
require "elastic_graph/json_ingestion/schema_definition/schema_elements/has_json_schema"

module ElasticGraph
  module JSONIngestion
    module SchemaDefinition
      # Namespace for schema-element extensions that contribute JSON schema generation and validation.
      module SchemaElements
        # Extends schema-definition fields with JSON schema validation behavior.
        module FieldExtension
          include HasJSONSchema

          # @return [Boolean] whether this field has been marked as non-nullable in the JSON schema
          def non_nullable_in_json_schema?
            !!@non_nullable_in_json_schema
          end

          # Defines the [JSON schema](https://json-schema.org/understanding-json-schema/) validations for this field.
          # Validations defined here will be included in the generated `json_schemas.yaml` artifact, which is used by
          # the ElasticGraph indexer to validate events before indexing their data in the datastore. In addition, the
          # publisher may use `json_schemas.yaml` for code generation and to apply validation before publishing an
          # event to ElasticGraph.
          #
          # Can be called multiple times; each time, the options will be merged into the existing options.
          #
          # On a {ElasticGraph::SchemaDefinition::SchemaElements::Field}, this is optional, but can be used to make the
          # JSON schema validation stricter than it would otherwise be. For example, you could use
          # `json_schema maxLength: 30` on a `String` field to limit the length.
          #
          # You can use any of the JSON schema validation keywords here. In addition, `nullable: false` is supported
          # to configure the generated JSON schema to disallow `null` values for the field. Note that if you define a
          # field with a non-nullable GraphQL type (e.g. `Int!`), the JSON schema will automatically disallow nulls.
          # However, as explained in the {ElasticGraph::SchemaDefinition::SchemaElements::TypeWithSubfields#field}
          # documentation, we generally recommend against defining non-nullable GraphQL fields.
          # `json_schema nullable: false` will disallow `null` values from being indexed, while still keeping the
          # field nullable in the GraphQL schema. If you think you might want to make a field non-nullable in the
          # GraphQL schema some day, it's a good idea to use `json_schema nullable: false` now to ensure every indexed
          # record has a non-null value for the field.
          #
          # @note We recommend using JSON schema validations in a limited fashion. Validations that are appropriate to
          #   apply when data is entering the system-of-record are often not appropriate on a secondary index like
          #   ElasticGraph. Events that violate a JSON schema validation will fail to index (typically they will be
          #   sent to the dead letter queue and page an oncall engineer). If an ElasticGraph instance is meant to
          #   contain all the data of some source system, you probably don't want it applying stricter validations
          #   than the source system itself has. We recommend limiting your JSON schema validations to situations
          #   where violations would prevent ElasticGraph from operating correctly.
          #
          # @param nullable [Boolean, nil] set to `false` to make this field non-nullable in the JSON schema
          # @param options [Hash<Symbol, Object>] additional JSON schema options
          # @return [void]
          #
          # @example Define additional validations on a field
          #   ElasticGraph.define_schema do |schema|
          #     schema.object_type "Card" do |t|
          #       t.field "id", "ID!"
          #
          #       t.field "expYear", "Int" do |f|
          #         # Use JSON schema to ensure the publisher is sending us 4 digit years, not 2 digit years.
          #         f.json_schema minimum: 2000, maximum: 2099
          #       end
          #
          #       t.field "expMonth", "Int" do |f|
          #         f.json_schema minimum: 1, maximum: 12
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

            super(**options)
          end

          # Registers an old name that this field used to have in a prior JSON schema version.
          #
          # @note In situations where this API applies, ElasticGraph will give you an error message indicating that you need to use this API
          #   or {TypeWithSubfieldsExtension#deleted_field}. Likewise, when ElasticGraph no longer needs to know about this, it'll give you a warning
          #   indicating the call to this method can be removed.
          #
          # @param old_name [String] old name this field used to have in a prior version of the schema
          # @return [void]
          #
          # @example Indicate that `Widget.description` used to be called `Widget.notes`.
          #   ElasticGraph.define_schema do |schema|
          #     schema.object_type "Widget" do |t|
          #       t.field "description", "String" do |f|
          #         f.renamed_from "notes"
          #       end
          #     end
          #   end
          def renamed_from(old_name)
            json_ingestion_state.register_renamed_field(
              parent_type.name,
              from: old_name,
              to: name,
              defined_at: caller_locations(1, 1).to_a.first, # : ::Thread::Backtrace::Location
              defined_via: %(field.renamed_from "#{old_name}")
            )
          end

          # @private
          def to_indexing_field_reference
            reference = super
            return nil unless reference

            type_for_json_schema = non_nullable_in_json_schema? ? type.wrap_non_null : type

            Indexing::FieldReference.new(
              reference.with(type: type_for_json_schema),
              json_schema_layers: JSONSchemaLayers.for(type_for_json_schema),
              json_schema_customizations: json_schema_options,
              doc_comment: doc_comment
            )
          end

          private

          def json_ingestion_state
            extension_state = schema_def_state # : ::ElasticGraph::SchemaDefinition::State & SchemaDefinition::StateExtension
            extension_state.json_ingestion_state
          end
        end
      end
    end
  end
end
