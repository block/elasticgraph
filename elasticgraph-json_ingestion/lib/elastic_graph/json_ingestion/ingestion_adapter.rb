# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/constants"
require "elastic_graph/indexer/event_id"
require "elastic_graph/indexer/ingestion_adapter"
require "elastic_graph/json_ingestion/record_preparer_factory"
require "elastic_graph/support/json_schema/validator_factory"

module ElasticGraph
  module JSONIngestion
    # Ingestion adapter for events in ElasticGraph's versioned JSON format: it validates events
    # against the JSON schema identified by the event's `json_schema_version`, and prepares
    # records using that version's view of the schema. Made available to the indexer by the
    # {IndexerExtension} that {SchemaDefinition::APIExtension} registers.
    class IngestionAdapter
      # Shorthand for the result type defined by the indexer's ingestion adapter interface.
      ValidationResult = Indexer::IngestionAdapter::ValidationResult
      private_constant :ValidationResult

      # @param schema_artifacts [SchemaArtifacts::FromDisk] the schema artifacts
      # @param logger [Logger] the ElasticGraph logger
      # @param configure_record_validator [Proc, nil] optional callback to further configure the record validator
      def initialize(schema_artifacts:, logger:, configure_record_validator: nil)
        @schema_artifacts = schema_artifacts
        @logger = logger
        @configure_record_validator = configure_record_validator
        @record_preparer_factory = RecordPreparerFactory.new(schema_artifacts)
      end

      # Indicates whether this adapter recognizes the given event as one of its own, based on the
      # presence of the `json_schema_version` field in the event envelope.
      #
      # @param event [Hash<String, Object>] an ElasticGraph indexing event
      # @return [Boolean] whether this adapter handles the event
      def handles_event?(event)
        event.key?(JSON_SCHEMA_VERSION_KEY)
      end

      # Validates the given event and resolves the record preparer appropriate for the event's
      # JSON schema version.
      #
      # @param event [Hash<String, Object>] an ElasticGraph indexing event
      # @return [Indexer::IngestionAdapter::ValidationResult] the result of validating the event
      def validate_event(event)
        selected_json_schema_version = select_json_schema_version(event) { |failure| return failure }

        # Because the `select_json_schema_version` picks the closest-matching json schema version, the incoming
        # event might not match the expected json_schema_version value in the json schema (which is a `const` field).
        # This is by design, since we're picking a schema based on best-effort, so to avoid that by-design validation error,
        # performing the envelope validation on a "patched" version of the event.
        event_with_patched_envelope = event.merge({JSON_SCHEMA_VERSION_KEY => selected_json_schema_version})

        if (error_message = validator(EVENT_ENVELOPE_JSON_SCHEMA_NAME, selected_json_schema_version).validate_with_error_message(event_with_patched_envelope))
          return ValidationResult.invalid(payload_description: "event payload", message: error_message)
        end

        record = event.fetch("record")
        graphql_type_name = event.fetch("type")

        if (error_message = validator(graphql_type_name, selected_json_schema_version).validate_with_error_message(record))
          return ValidationResult.invalid(payload_description: "#{graphql_type_name} record", message: error_message)
        end

        ValidationResult.valid(@record_preparer_factory.for_json_schema_version(selected_json_schema_version))
      end

      private

      def select_json_schema_version(event)
        available_json_schema_versions = @schema_artifacts.available_json_schema_versions

        requested_json_schema_version = event[JSON_SCHEMA_VERSION_KEY]

        # First check that a valid value has been requested (a positive integer)
        if !event.key?(JSON_SCHEMA_VERSION_KEY)
          yield ValidationResult.invalid(payload_description: JSON_SCHEMA_VERSION_KEY, message: "Event lacks a `#{JSON_SCHEMA_VERSION_KEY}`")
        elsif !requested_json_schema_version.is_a?(Integer) || requested_json_schema_version < 1
          yield ValidationResult.invalid(payload_description: JSON_SCHEMA_VERSION_KEY, message: "#{JSON_SCHEMA_VERSION_KEY} (#{requested_json_schema_version}) must be a positive integer.")
        end

        # The requested version might not necessarily be available (if the publisher is deployed ahead of the indexer, or an old schema
        # version is removed prematurely, or an indexer deployment is rolled back). So the behavior is to always pick the closest-available
        # version. If there's an exact match, great. Even if not an exact match, if the incoming event payload conforms to the closest match,
        # the event can still be indexed.
        #
        # This min_by block will take the closest version in the list. If a tie occurs, the first value in the list wins. The desired
        # behavior is in the event of a tie (highly unlikely, there shouldn't be a gap in available json schema versions), the higher version
        # should be selected. So to get that behavior, the list is sorted in descending order.
        #
        selected_json_schema_version = available_json_schema_versions.sort.reverse.min_by { |version| (requested_json_schema_version - version).abs }

        if selected_json_schema_version != requested_json_schema_version
          @logger.info({
            "message_type" => "ElasticGraphMissingJSONSchemaVersion",
            "message_id" => event["message_id"],
            "event_id" => Indexer::EventID.from_event(event),
            "event_type" => event["type"],
            "requested_json_schema_version" => requested_json_schema_version,
            "selected_json_schema_version" => selected_json_schema_version
          })
        end

        if selected_json_schema_version.nil?
          yield ValidationResult.invalid(
            payload_description: JSON_SCHEMA_VERSION_KEY,
            message: "Failed to select json schema version. Requested version: #{event[JSON_SCHEMA_VERSION_KEY]}. \
            Available json schema versions: #{available_json_schema_versions.sort.join(", ")}"
          )
        end

        selected_json_schema_version
      end

      def validator(type, selected_json_schema_version)
        factory = validator_factories_by_version[selected_json_schema_version] # : Support::JSONSchema::ValidatorFactory
        factory.validator_for(type)
      end

      def validator_factories_by_version
        @validator_factories_by_version ||= ::Hash.new do |hash, json_schema_version|
          factory = Support::JSONSchema::ValidatorFactory.new(
            schema: @schema_artifacts.json_schemas_for(json_schema_version),
            sanitize_pii: true
          )

          if (configure_record_validator = @configure_record_validator)
            factory = configure_record_validator.call(factory)
          end

          hash[json_schema_version] = factory
        end
      end

      # :nocov: -- this should not be called. Instead, it exists to guard against wrongly raising an error from this class.
      def raise(*args)
        super("`raise` was called on `JSONIngestion::IngestionAdapter`, but should not. Instead, use " \
          "`yield ValidationResult.invalid(...)` so that we can accumulate all invalid events and allow " \
          "the valid events to still be processed.")
      end
      # :nocov:
    end
  end
end
