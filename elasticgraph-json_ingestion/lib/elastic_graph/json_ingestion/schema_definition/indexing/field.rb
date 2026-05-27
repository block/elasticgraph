# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "delegate"
require "elastic_graph/constants"
require "elastic_graph/json_ingestion/schema_definition/indexing/json_schema_field_metadata"
require "elastic_graph/schema_definition/indexing/field"
require "elastic_graph/support/hash_util"

module ElasticGraph
  module JSONIngestion
    module SchemaDefinition
      # Namespace for JSON-schema-aware indexing components.
      module Indexing
        # Wraps an indexing field with JSON schema generation behavior.
        #
        # @api private
        class Field < DelegateClass(ElasticGraph::SchemaDefinition::Indexing::Field)
          # @dynamic __getobj__, json_schema_layers, json_schema_customizations
          # @return [Array<Symbol>] JSON schema wrapper layers from the field type reference
          attr_reader :json_schema_layers

          # @return [Hash<Symbol, Object>] user-defined JSON schema customizations
          attr_reader :json_schema_customizations

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

          # @param field [ElasticGraph::SchemaDefinition::Indexing::Field] the indexing field to wrap
          # @param json_schema_layers [Array<Symbol>] JSON schema wrapper layers from the field type reference
          # @param json_schema_customizations [Hash<Symbol, Object>] user-defined JSON schema customizations
          def initialize(field, json_schema_layers:, json_schema_customizations:)
            super(field)
            @json_schema_layers = json_schema_layers
            @json_schema_customizations = json_schema_customizations
          end

          # Returns the JSON schema definition for this field.
          #
          # @return [Hash<String, Object>] the JSON schema hash
          def json_schema
            @json_schema ||=
              json_schema_layers
                .reverse # resolve layers from innermost to outermost wrappings
                .reduce(inner_json_schema) { |acc, layer| process_layer(layer, acc) }
                .merge(outer_json_schema_customizations)
                .merge({"description" => doc_comment}.compact)
                .then { |hash| Support::HashUtil.stringify_keys(hash) }
          end

          # @return [JSONSchemaFieldMetadata] metadata about this field for inclusion in the JSON schema
          def json_schema_metadata
            JSONSchemaFieldMetadata.new(type: type.name, name_in_index: name_in_index)
          end

          def nullable?
            json_schema_layers.include?(:nullable)
          end

          # Compares fields, including JSON schema metadata tracked by this wrapper.
          #
          # @param other [Object] the object to compare against
          # @return [Boolean] true when the field and JSON schema metadata match
          def ==(other)
            case other
            when Field
              __getobj__ == other.__getobj__ &&
                json_schema_layers == other.json_schema_layers &&
                json_schema_customizations == other.json_schema_customizations
            else
              super
            end
          end

          def eql?(other)
            self == other
          end

          # Returns a hash code based on the wrapped field and JSON schema metadata.
          #
          # @return [Integer] the hash code
          def hash
            [__getobj__, json_schema_layers, json_schema_customizations].hash
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
            # @type var field_type: _JSONFieldType
            field_type = _ = indexing_field_type
            customizations = field_type.format_field_json_schema_customizations(customizations)

            ref = {"$ref" => "#/$defs/#{type.unwrapped_name}"}
            return ref if customizations.empty?

            # Combine any customizations with the type ref under an "allOf" subschema:
            # all of these properties must hold true for the type to be valid.
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
            when :array
              {"type" => "array", "items" => schema}
            else
              # :nocov: - layer is only ever `:nullable` or `:array` so we never get here.
              schema
              # :nocov:
            end
          end
        end
      end
    end
  end
end
