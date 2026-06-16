# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/constants"
require "elastic_graph/errors"
require "elastic_graph/json_ingestion/schema_definition/indexing/json_schema_with_metadata"
require "elastic_graph/json_ingestion/schema_definition/json_schema_builder"

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
          json_ingestion_state.json_schema_version_setter_location
        end

        # @private
        def json_schema_field_metadata_by_type_and_field_name
          @json_schema_field_metadata_by_type_and_field_name ||= json_ingestion_json_schema_builder.field_metadata_by_type_and_field_name
        end

        # @private
        def current_public_json_schema
          @current_public_json_schema ||= json_ingestion_json_schema_builder.public_json_schema
        end

        # @private
        def merge_field_metadata_into_json_schema(json_schema)
          json_ingestion_json_schema_with_metadata_merger.merge_metadata_into(json_schema)
        end

        # @private
        def unused_deprecated_elements
          json_ingestion_json_schema_with_metadata_merger.unused_deprecated_elements
        end

        private

        # Returns the wrapped state narrowed to include this gem's `StateExtension`. Centralizes
        # the Steep cast that's needed because Steep can't see the `extend(StateExtension)` applied
        # at runtime in {APIExtension.extended}.
        def json_ingestion_state
          state # : ElasticGraph::SchemaDefinition::State & StateExtension
        end

        def json_ingestion_json_schema_builder
          @json_ingestion_json_schema_builder ||= begin
            # Force `all_types` to materialize before iterating `state.types_by_name`. Reading `all_types`
            # runs the `on_built_in_types` callbacks, including the GeoLocation JSON schema field
            # customizations registered by `APIExtension.extended`.
            materialized_all_types = all_types

            JSONSchemaBuilder.new(
              state: json_ingestion_state,
              all_types: materialized_all_types,
              derived_indexing_type_names: derived_indexing_type_names
            )
          end
        end

        def json_ingestion_json_schema_with_metadata_merger
          @json_ingestion_json_schema_with_metadata_merger ||= Indexing::JSONSchemaWithMetadata::Merger.new(self)
        end
      end
    end
  end
end
