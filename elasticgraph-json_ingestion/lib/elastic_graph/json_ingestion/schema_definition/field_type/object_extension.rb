# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "delegate"
require "elastic_graph/support/hash_util"

module ElasticGraph
  module JSONIngestion
    module SchemaDefinition
      # Namespace for JSON-schema-aware wrappers around core indexing field types.
      module FieldType
        # Wraps an object/interface indexing field type to add JSON schema serialization.
        class Object < ::SimpleDelegator
          # @param wrapped [ElasticGraph::SchemaDefinition::Indexing::FieldType::Object] the core field type to wrap
          # @param json_schema_options [Hash<Symbol, Object>] JSON schema options from the type definition
          def initialize(wrapped, json_schema_options: {})
            @json_schema_options = json_schema_options
            super(wrapped)
          end

          # @return [Hash<String, JSONSchemaFieldMetadata>] field metadata keyed by field name
          def json_schema_field_metadata_by_field_name
            __getobj__.subfields.to_h { |field| [field.name, field.json_schema_metadata] }
          end

          # Returns the customizations as-is for object types.
          #
          # @param customizations [Hash<String, Object>] the customizations to format
          # @return [Hash<String, Object>] the formatted customizations
          def format_field_json_schema_customizations(customizations)
            customizations
          end

          # @return [Hash<String, Object>] the JSON schema definition for this object type
          def to_json_schema
            wrapped = __getobj__
            ingestion_state = wrapped.schema_def_state.ingestion_serializer_state

            @to_json_schema ||=
              if @json_schema_options.empty?
                other_source_subfields, json_schema_candidate_subfields = wrapped.subfields.partition(&:source)
                validate_sourced_fields_have_no_json_schema_overrides(other_source_subfields)
                json_schema_subfields = json_schema_candidate_subfields.reject(&:runtime_field_script)
                required_fields = json_schema_subfields
                required_fields = required_fields.reject(&:nullable?) if ingestion_state[:allow_omitted_json_schema_fields]

                {
                  "type" => "object",
                  "properties" => json_schema_subfields.to_h { |field| [field.name, field.json_schema] }.merge(json_schema_typename_field),
                  "required" => required_fields.map(&:name).freeze,
                  "additionalProperties" => (false unless ingestion_state[:allow_extra_json_schema_fields]),
                  "description" => wrapped.doc_comment
                }.compact.freeze
              else
                Support::HashUtil.stringify_keys(@json_schema_options)
              end
          end

          private

          def json_schema_typename_field
            type_name = __getobj__.type_name

            {
              "__typename" => {
                "type" => "string",
                "const" => type_name,
                "default" => type_name
              }
            }
          end

          def validate_sourced_fields_have_no_json_schema_overrides(other_source_subfields)
            problem_fields = other_source_subfields.reject { |field| field.json_schema_customizations.empty? }
            return if problem_fields.empty?

            field_descriptions = problem_fields.map(&:name).sort.map { |field| "`#{field}`" }.join(", ")
            raise Errors::SchemaError,
              "`#{type_name}` has #{problem_fields.size} field(s) (#{field_descriptions}) that are `sourced_from` " \
              "another type and also have JSON schema customizations. Instead, put the JSON schema " \
              "customizations on the source type's field definitions."
          end
        end
      end
    end
  end
end
