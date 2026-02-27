# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/support/json_schema/validator_factory"

module ElasticGraph
  class Indexer
    module IngestionSchemas
      # Default ingestion schema implementation based on ElasticGraph JSON schema artifacts.
      class JSONSchema
        # Builds an ingestion schema adapter over ElasticGraph JSON schema artifacts.
        def initialize(schema_artifacts:, record_preparer_factory:, configure_record_validator:)
          @schema_artifacts = schema_artifacts
          @record_preparer_factory = record_preparer_factory
          @configure_record_validator = configure_record_validator
        end

        # Returns all known JSON schema versions that can be selected for ingestion.
        def available_versions
          @schema_artifacts.available_json_schema_versions
        end

        # Returns a validator for the given type and JSON schema version.
        def validator_for(type, version)
          factory = validator_factories_by_version[version] # : Support::JSONSchema::ValidatorFactory
          factory.validator_for(type)
        end

        # Returns a record preparer configured for the given JSON schema version.
        def record_preparer_for(version)
          @record_preparer_factory.for_json_schema_version(version)
        end

        private

        # Lazily builds and memoizes validator factories by schema version.
        def validator_factories_by_version
          @validator_factories_by_version ||= ::Hash.new do |hash, schema_version|
            factory = Support::JSONSchema::ValidatorFactory.new(
              schema: @schema_artifacts.json_schemas_for(schema_version),
              sanitize_pii: true
            )
            factory = @configure_record_validator.call(factory) if @configure_record_validator
            hash[schema_version] = factory
          end
        end
      end
    end
  end
end
