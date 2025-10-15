# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/errors"
require "elastic_graph/support/hash_util"
require "elastic_graph/support/memoizable_data"

module ElasticGraph
  module SchemaDefinition
    module Indexing
      module FieldType
        # Responsible for the JSON schema and mapping of a {SchemaElements::ObjectType}.
        #
        # @!attribute [r] type_name
        #   @return [String] name of the object type
        # @!attribute [r] subfields
        #   @return [Array<Field>] the subfields of this object type
        # @!attribute [r] mapping_options
        #   @return [Hash<String, ::Object>] options to be included in the mapping
        # @!attribute [r] json_schema_options
        #   @return [Hash<String, ::Object>] options to be included in the JSON schema
        # @!attribute [r] doc_comment
        #   @return [String, nil] documentation for the type
        #
        # @api private
        class Object < Support::MemoizableData.define(:type_name, :subfields, :mapping_options, :json_schema_options, :doc_comment)
          # @return [Hash<String, ::Object>] the datastore mapping for this object type.
          def to_mapping
            @to_mapping ||= begin
              base_mapping = Field.normalized_mapping_hash_for(subfields)
              # When a custom mapping type is used, we need to omit `properties`, because custom mapping
              # types generally don't use `properties` (and if you need to use `properties` with a custom
              # type, you're responsible for defining the properties).
              base_mapping = base_mapping.except("properties") if (mapping_options[:type] || "object") != "object"
              base_mapping.merge(Support::HashUtil.stringify_keys(mapping_options))
            end
          end

          # @return [Hash<String, ::Object>] the JSON schema for this object type.
          def to_json_schema
            @to_json_schema ||=
              if json_schema_options.empty?
                # Fields that are `sourced_from` an alternate type must not be included in this types JSON schema,
                # since events of this type won't include them.
                other_source_subfields, json_schema_candidate_subfields = subfields.partition(&:source)
                validate_sourced_fields_have_no_json_schema_overrides(other_source_subfields)
                json_schema_subfields = json_schema_candidate_subfields.reject(&:runtime_field_script)

                {
                  "type" => "object",
                  "properties" => json_schema_subfields.to_h { |f| [f.name, f.json_schema] }.merge(json_schema_typename_field),
                  # Note: `__typename` is intentionally not included in the `required` list. If `__typename` is present
                  # we want it validated (as we do by merging in `json_schema_typename_field`) but we only want
                  # to require it in the context of a union type. The union's json schema requires the field.
                  "required" => json_schema_subfields.map(&:name).freeze,
                  "description" => doc_comment
                }.compact.freeze
              else
                Support::HashUtil.stringify_keys(json_schema_options)
              end
          end

          # @return [Hash<String, ::Object>] additional ElasticGraph metadata to put in the JSON schema for this object type.
          def json_schema_field_metadata_by_field_name
            subfields.to_h { |f| [f.name, f.json_schema_metadata] }
          end

          # @param customizations [Hash<String, ::Object>] JSON schema customizations
          # @return [Hash<String, ::Object>] formatted customizations.
          def format_field_json_schema_customizations(customizations)
            customizations
          end

          private

          def after_initialize
            subfields.freeze
          end

          # Returns a __typename property which we use for union types.
          #
          # This must always be set to the name of the type (thus the const value).
          #
          # We also add a "default" value. This does not impact validation, but rather
          # aids tools like our kotlin codegen to save publishers from having to set the
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
            problem_fields = other_source_subfields.reject { |f| f.json_schema_customizations.empty? }
            return if problem_fields.empty?

            field_descriptions = problem_fields.map(&:name).sort.map { |f| "`#{f}`" }.join(", ")
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
