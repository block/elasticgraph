# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/constants"
require "elastic_graph/errors"
require "elastic_graph/json_ingestion/schema_definition/indexing/event_envelope"

module ElasticGraph
  module JSONIngestion
    module SchemaDefinition
      # Builds JSON schema data from schema definition results.
      #
      # @private
      class JSONSchemaBuilder
        def initialize(state:, all_types:, derived_indexing_type_names:)
          @state = state
          @all_types = all_types
          @derived_indexing_type_names = derived_indexing_type_names
        end

        def public_json_schema
          json_schema_version = @state.json_schema_version
          if json_schema_version.nil?
            raise Errors::SchemaError, "`json_schema_version` must be specified in the schema. To resolve, add `schema.json_schema_version 1` in a schema definition block."
          end

          {
            "$schema" => JSON_META_SCHEMA,
            JSON_SCHEMA_VERSION_KEY => json_schema_version,
            "$defs" => {
              "ElasticGraphEventEnvelope" => Indexing::EventEnvelope.json_schema(root_document_type_names, json_schema_version)
            }.merge(definitions_by_name)
          }
        end

        def field_metadata_by_type_and_field_name
          indexing_field_types_by_name.transform_values(&:json_schema_field_metadata_by_field_name)
        end

        private

        def root_document_type_names
          @state.object_types_by_name.values
            .select { |type| type.root_document_type? && !type.abstract? }
            .reject { |type| @derived_indexing_type_names.include?(type.name) }
            .map(&:name)
        end

        def definitions_by_name
          indexing_field_types_by_name
            .transform_values(&:to_json_schema)
            .compact
        end

        def indexing_field_types_by_name
          @indexing_field_types_by_name ||= @state
            .types_by_name
            .except("Query")
            .values
            .reject do |type|
              @derived_indexing_type_names.include?(type.name) ||
                # Skip graphql framework types.
                type.graphql_only?
            end
            .sort_by(&:name)
            .to_h do |type|
              # @type var indexing_field_type: Indexing::_JSONFieldType
              indexing_field_type = _ = type.to_indexing_field_type
              [type.name, indexing_field_type]
            end
        end
      end
    end
  end
end
