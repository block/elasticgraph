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
require "elastic_graph/json_ingestion/schema_definition/indexing/json_schema_with_metadata"

module ElasticGraph
  module JSONIngestion
    module SchemaDefinition
      # Extension module for {ElasticGraph::SchemaDefinition::Results} that adds
      # JSON Schema generation support.
      #
      # @private
      module ResultsExtension
        # @param version [Integer] desired JSON schema version
        # @return [Hash<String, Object>] the JSON schema for the requested version, if available
        # @raise [Errors::NotFoundError] if the requested JSON schema version is not available
        def json_schemas_for(version)
          unless available_json_schema_versions.include?(version)
            raise Errors::NotFoundError, "The requested json schema version (#{version}) is not available. Available versions: #{available_json_schema_versions.to_a.join(", ")}."
          end

          @latest_versioned_json_schema ||= merge_field_metadata_into_json_schema(current_public_json_schema).json_schema
        end

        # @return [Set<Integer>] set of available JSON schema versions
        def available_json_schema_versions
          @available_json_schema_versions ||= Set[latest_json_schema_version]
        end

        # @return [Integer] the current JSON schema version
        def latest_json_schema_version
          current_public_json_schema[JSON_SCHEMA_VERSION_KEY]
        end

        # @private
        def json_schema_version_setter_location
          state.ingestion_serializer_state[:json_schema_version_setter_location]
        end

        # @private
        def json_schema_field_metadata_by_type_and_field_name
          @json_schema_field_metadata_by_type_and_field_name ||= json_schema_indexing_field_types_by_name
            .transform_values(&:json_schema_field_metadata_by_field_name)
        end

        # @private
        def current_public_json_schema
          @current_public_json_schema ||= build_public_json_schema
        end

        # @private
        def merge_field_metadata_into_json_schema(json_schema)
          json_schema_with_metadata_merger.merge_metadata_into(json_schema)
        end

        # @private
        def unused_deprecated_elements
          json_schema_with_metadata_merger.unused_deprecated_elements
        end

        private

        def json_schema_with_metadata_merger
          @json_schema_with_metadata_merger ||= Indexing::JSONSchemaWithMetadata::Merger.new(self)
        end

        def build_public_json_schema
          json_schema_version = state.ingestion_serializer_state[:json_schema_version]
          if json_schema_version.nil?
            raise Errors::SchemaError, "`json_schema_version` must be specified in the schema. To resolve, add `schema.json_schema_version 1` in a schema definition block."
          end

          root_document_type_names = state.object_types_by_name.values
            .select { |type| type.root_document_type? && !type.abstract? }
            .reject { |type| derived_indexing_type_names.include?(type.name) }
            .map(&:name)

          definitions_by_name = json_schema_indexing_field_types_by_name
            .transform_values(&:to_json_schema)
            .compact

          {
            "$schema" => JSON_META_SCHEMA,
            JSON_SCHEMA_VERSION_KEY => json_schema_version,
            "$defs" => {
              "ElasticGraphEventEnvelope" => Indexing::EventEnvelope.json_schema(root_document_type_names, json_schema_version)
            }.merge(definitions_by_name)
          }
        end

        def json_schema_indexing_field_types_by_name
          @json_schema_indexing_field_types_by_name ||= state
            .types_by_name
            .except("Query")
            .values
            .reject do |t|
              derived_indexing_type_names.include?(t.name) ||
                # Skip graphql framework types
                t.graphql_only?
            end
            .sort_by(&:name)
            .to_h { |type| [type.name, type.to_indexing_field_type] }
        end
      end
    end
  end
end
