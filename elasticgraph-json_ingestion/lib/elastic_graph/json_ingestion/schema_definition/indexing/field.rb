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
require "elastic_graph/support/hash_util"

module ElasticGraph
  module JSONIngestion
    module SchemaDefinition
      # Namespace for JSON-schema-aware indexing components.
      module Indexing
        # Wraps an indexing field with JSON schema generation behavior.
        #
        # @api private
        class Field < ::SimpleDelegator
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

          # @return [Hash<Symbol, Object>] user-specified JSON schema customizations for this field
          attr_reader :json_schema_customizations

          # @private
          def initialize(field, json_schema_layers:, json_schema_customizations:)
            @json_schema_layers = json_schema_layers
            @json_schema_customizations = json_schema_customizations
            super(field)
          end

          # Returns the JSON schema definition for this field.
          #
          # @return [Hash<String, Object>] the JSON schema hash
          def json_schema
            @json_schema ||=
              json_schema_layers
                .reverse
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

          private

          attr_reader :json_schema_layers

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

            {"allOf" => [ref, customizations]}
          end

          def outer_json_schema_customizations
            return {} unless user_specified_json_schema_customizations_go_on_outside?
            Support::HashUtil.stringify_keys(json_schema_customizations)
          end

          def user_specified_json_schema_customizations_go_on_outside?
            json_schema_layers.include?(:array)
          end

          def process_layer(layer, schema)
            case layer
            when :nullable
              {
                "anyOf" => [
                  schema,
                  {"type" => "null"}
                ]
              }
            when :array
              {"type" => "array", "items" => schema}
            end
          end
        end
      end
    end
  end
end
