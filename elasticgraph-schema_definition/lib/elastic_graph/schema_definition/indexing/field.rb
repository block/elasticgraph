# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/constants"
require "elastic_graph/schema_definition/indexing/json_schema_field_metadata"
require "elastic_graph/schema_definition/indexing/list_counts_mapping"
require "elastic_graph/support/hash_util"
require "elastic_graph/support/memoizable_data"

module ElasticGraph
  module SchemaDefinition
    module Indexing
      # Represents a field in a JSON document during indexing.
      #
      # @api private
      class Field < Support::MemoizableData.define(
        :name,
        :name_in_index,
        :type,
        :json_schema_layers,
        :indexing_field_type,
        :accuracy_confidence,
        :json_schema_customizations,
        :mapping_customizations,
        :source,
        :runtime_field_script,
        :doc_comment
      )
        # JSON schema overrides that automatically apply to specific mapping types so that the JSON schema
        # validation will reject values which cannot be indexed into fields of a specific mapping type.
        #
        # @see https://www.elastic.co/guide/en/elasticsearch/reference/current/number.html Elasticsearch numeric field type documentation
        # @note We don't handle `integer` here because it's the default numeric type (handled by our definition of the `Int` scalar type).
        # @note Likewise, we don't handle `long` here because a custom scalar type must be used for that since GraphQL's `Int` type can't handle long values.
        JSON_SCHEMA_OVERRIDES_BY_MAPPING_TYPE = {
          "byte" => {"minimum" => -(2**7), "maximum" => (2**7) - 1},
          "short" => {"minimum" => -(2**15), "maximum" => (2**15) - 1},
          "keyword" => {"maxLength" => DEFAULT_MAX_KEYWORD_LENGTH},
          "text" => {"maxLength" => DEFAULT_MAX_TEXT_LENGTH}
        }

        # @return [Hash<String, Object>] the mapping for this field. The returned hash should be composed entirely
        #   of Ruby primitives that, when converted to a JSON string, match the structure required by
        #   [Elasticsearch](https://www.elastic.co/guide/en/elasticsearch/reference/current/mapping.html).
        def mapping
          @mapping ||= begin
            raw_mapping = indexing_field_type
              .to_mapping
              .merge(Support::HashUtil.stringify_keys(mapping_customizations))

            if (object_type = type.fully_unwrapped.as_object_type) && type.list? && mapping_customizations[:type] == "nested"
              # If it's an object list field using the `nested` type, we need to add a `__counts` field to
              # the mapping for all of its subfields which are lists.
              ListCountsMapping.merged_into(raw_mapping, for_type: object_type)
            else
              raw_mapping
            end
          end
        end

        # @return [Hash<String, Object>] the JSON schema definition for this field. The returned object should
        #   be composed entirely of Ruby primitives that, when converted to a JSON string, match the
        #   requirements of [the JSON schema spec](https://json-schema.org/).
        def json_schema
          json_schema_layers
            .reverse # resolve layers from innermost to outermost wrappings
            .reduce(inner_json_schema) { |acc, layer| process_layer(layer, acc) }
            .merge(outer_json_schema_customizations)
            .merge({"description" => doc_comment}.compact)
            .then { |h| Support::HashUtil.stringify_keys(h) }
        end

        # @return [JSONSchemaFieldMetadata] additional ElasticGraph metadata to be stored in the JSON schema for this field.
        def json_schema_metadata
          JSONSchemaFieldMetadata.new(type: type.name, name_in_index: name_in_index)
        end

        # Builds a hash containing the mapping for the provided fields, normalizing it in the same way that the
        # datastore does so that consistency checks between our index configuration and what's in the datastore
        # work properly.
        #
        # @param fields [Array<Field>] fields to generate a mapping hash from
        # @return [Hash<String, Object>] generated mapping hash
        def self.normalized_mapping_hash_for(fields)
          # When an object field has `properties`, the datastore normalizes the mapping by dropping
          # the `type => object` (it's implicit, as `properties` are only valid on an object...).
          # OTOH, when there are no properties, the datastore normalizes the mapping by dropping the
          # empty `properties` entry and instead returning `type => object`.
          return {"type" => "object"} if fields.empty?

          # Partition the fields into runtime fields and normal fields based on the presence of runtime_script
          runtime_fields, normal_fields = fields.partition(&:runtime_field_script)

          mapping_hash = {
            "properties" => normal_fields.to_h { |f| [f.name_in_index, f.mapping] }
          }
          unless runtime_fields.empty?
            mapping_hash["runtime"] = runtime_fields.to_h do |f|
              [f.name_in_index, f.mapping.merge({"script" => {"source" => f.runtime_field_script}})]
            end
          end

          mapping_hash
        end

        def nullable?
          json_schema_layers.include?(:nullable)
        end

        private

        def inner_json_schema
          user_specified_customizations =
            if user_specified_json_schema_customizations_go_on_outside?
              {} # : ::Hash[::String, untyped]
            else
              Support::HashUtil.stringify_keys(json_schema_customizations)
            end

          customizations_from_mapping = JSON_SCHEMA_OVERRIDES_BY_MAPPING_TYPE[mapping["type"]] || {}
          customizations = customizations_from_mapping.merge(user_specified_customizations)
          customizations = indexing_field_type.format_field_json_schema_customizations(customizations)

          ref = {"$ref" => "#/$defs/#{type.unwrapped_name}"}
          return ref if customizations.empty?

          # Combine any customizations with type ref under an "allOf" subschema:
          # All of these properties must hold true for the type to be valid.
          #
          # Note that if we simply combine the customizations with the `$ref`
          # at the same level, it will not work, because other subschema
          # properties are ignored when they are in the same object as a `$ref`:
          # https://github.com/json-schema-org/JSON-Schema-Test-Suite/blob/2.0.0/tests/draft7/ref.json#L165-L168
          {"allOf" => [ref, customizations]}
        end

        def outer_json_schema_customizations
          return {} unless user_specified_json_schema_customizations_go_on_outside?
          Support::HashUtil.stringify_keys(json_schema_customizations)
        end

        # Indicates if the user-specified JSON schema customizations should go on the inside
        # (where they normally go) or on the outside. They only go on the outside when it's
        # an array field, because then they apply to the array itself instead of the items in the
        # array.
        def user_specified_json_schema_customizations_go_on_outside?
          json_schema_layers.include?(:array)
        end

        def process_layer(layer, schema)
          case layer
          when :nullable
            make_nullable(schema)
          when :array
            make_array(schema)
          else
            # :nocov: - layer is only ever `:nullable` or `:array` so we never get here
            schema
            # :nocov:
          end
        end

        def make_nullable(schema)
          # Here we use "anyOf" to ensure that JSON can either match the schema OR null.
          #
          # (Using "oneOf" would mean that if we had a schema that also allowed null,
          # null would never be allowed, since "oneOf" must match exactly one subschema).
          {
            "anyOf" => [
              schema,
              {"type" => "null"}
            ]
          }
        end

        def make_array(schema)
          {"type" => "array", "items" => schema}
        end
      end
    end
  end
end
