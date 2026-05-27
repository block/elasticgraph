# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "delegate"
require "elastic_graph/errors"
require "elastic_graph/schema_definition/indexing/field_type/object"
require "elastic_graph/support/hash_util"

module ElasticGraph
  module JSONIngestion
    module SchemaDefinition
      module Indexing
        module FieldType
          # Wraps object/interface indexing field types with JSON schema serialization.
          #
          # @private
          class Object < DelegateClass(ElasticGraph::SchemaDefinition::Indexing::FieldType::Object)
            # @dynamic __getobj__, json_schema_options
            # @return [Hash<Symbol, Object>] JSON schema options for this object type
            attr_reader :json_schema_options

            # @param field_type [ElasticGraph::SchemaDefinition::Indexing::FieldType::Object] the object field type to wrap
            # @param json_schema_options [Hash<Symbol, Object>] JSON schema options for this object type
            def initialize(field_type, json_schema_options:)
              super(field_type)
              @json_schema_options = json_schema_options
            end

            # @return [Hash<String, JSONSchemaFieldMetadata>] field metadata keyed by field name
            def json_schema_field_metadata_by_field_name
              # @type var json_subfields: ::Array[Indexing::Field]
              json_subfields = _ = subfields
              json_subfields.to_h { |field| [field.name, field.json_schema_metadata] }
            end

            # @param customizations [Hash<String, Object>] the customizations to format
            # @return [Hash<String, Object>] the formatted customizations
            def format_field_json_schema_customizations(customizations)
              customizations
            end

            # @return [Hash<String, Object>] the JSON schema definition for this object type
            def to_json_schema
              # @type var state: ElasticGraph::SchemaDefinition::State & StateExtension
              state = _ = schema_def_state
              # @type var json_subfields: ::Array[Indexing::Field]
              json_subfields = _ = subfields

              @to_json_schema ||=
                if json_schema_options.empty?
                  # Fields that are `sourced_from` an alternate type must not be included in this type's JSON schema,
                  # since events of this type won't include them.
                  other_source_subfields, json_schema_candidate_subfields = json_subfields.partition(&:source)
                  validate_sourced_fields_have_no_json_schema_overrides(other_source_subfields)
                  json_schema_subfields = json_schema_candidate_subfields.reject(&:runtime_field_script)
                  required_fields = json_schema_subfields
                  required_fields = required_fields.reject(&:nullable?) if state.allow_omitted_json_schema_fields

                  {
                    "type" => "object",
                    "properties" => json_schema_subfields.to_h { |field| [field.name, field.json_schema] }.merge(json_schema_typename_field),
                    # Note: `__typename` is intentionally not included in the `required` list. If `__typename` is present
                    # we want it validated (as we do by merging in `json_schema_typename_field`) but we only want
                    # to require it in the context of a union type. The union's JSON schema requires the field.
                    "required" => required_fields.map(&:name).freeze,
                    "additionalProperties" => (false unless state.allow_extra_json_schema_fields),
                    "description" => doc_comment
                  }.compact.freeze
                else
                  Support::HashUtil.stringify_keys(json_schema_options)
                end
            end

            def ==(other)
              case other
              when Object
                __getobj__ == other.__getobj__ &&
                  json_schema_options == other.json_schema_options
              else
                super
              end
            end

            def eql?(other)
              self == other
            end

            def hash
              [__getobj__, json_schema_options].hash
            end

            private

            # Returns a `__typename` property which we use for union types.
            #
            # This must always be set to the name of the type (thus the const value).
            #
            # We also add a "default" value. This does not impact validation, but rather
            # aids tools like our Kotlin codegen to save publishers from having to set the
            # property explicitly when creating events.
            def json_schema_typename_field
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
end
