# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/constants"
require "elastic_graph/indexer/event"
require "elastic_graph/indexer/ingestion_adapter"
require "elastic_graph/indexer/malformed_event_error"
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
      ValidationResult = ElasticGraph::Indexer::IngestionAdapter::ValidationResult
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

      # Validates the envelope of each decoded JSON event and builds an {ElasticGraph::Indexer::Event}
      # for each valid one.
      #
      # @param decoded_events [Array<Hash<String, Object>>] decoded JSON indexing events
      # @return [Array(Array<ElasticGraph::Indexer::Event>, Array<ElasticGraph::Indexer::MalformedEventError>)]
      #   the events with a valid envelope, and a failure for each event with a malformed envelope
      def events_from(decoded_events)
        envelope_failures = decoded_events.map { |decoded_event| envelope_failure_for(decoded_event) }
        valid, malformed = decoded_events.zip(envelope_failures).partition { |(_, failure)| failure.nil? }

        [
          valid.map { |(decoded_event, _)| event_from(decoded_event) },
          malformed.filter_map { |(_, failure)| failure }
        ]
      end

      # Validates the record of the given event and resolves the record preparer appropriate for
      # the event's JSON schema version.
      #
      # @param event [ElasticGraph::Indexer::Event] an ElasticGraph indexing event
      # @param skip_record_validation [Boolean] whether to skip record validation
      # @return [ElasticGraph::Indexer::IngestionAdapter::ValidationResult] the result of validating the event
      def validate_event(event, skip_record_validation: false)
        selected_json_schema_version = closest_available_json_schema_version(event.schema_version) or raise

        # The datastore includes `id` in search payloads only when it is part of the indexed record.
        record = event.record.merge("id" => event.id)

        if !skip_record_validation && (error_message = validator(event.type, selected_json_schema_version).validate_with_error_message(record))
          return ValidationResult.invalid(validation_target: "#{event.type} record", message: error_message)
        end

        ValidationResult.valid(event.with(record: record), @record_preparer_factory.for_json_schema_version(selected_json_schema_version))
      end

      private

      # JSON has no integer type, so a publisher can encode `version` as `3.0`, which the envelope
      # schema accepts. The event needs an `Integer` version.
      def event_from(decoded_event)
        ElasticGraph::Indexer::Event.from_validated_hash(decoded_event.merge("version" => decoded_event.fetch("version").to_i))
      end

      def envelope_failure_for(decoded_event)
        requested_json_schema_version = decoded_event[JSON_SCHEMA_VERSION_KEY]

        # First check that a valid value has been requested (a positive integer)
        if !decoded_event.key?(JSON_SCHEMA_VERSION_KEY)
          return malformed(decoded_event, validation_target: JSON_SCHEMA_VERSION_KEY, message: "Event lacks a `#{JSON_SCHEMA_VERSION_KEY}`")
        elsif !requested_json_schema_version.is_a?(Integer) || requested_json_schema_version < 1
          return malformed(decoded_event, validation_target: JSON_SCHEMA_VERSION_KEY, message: "#{JSON_SCHEMA_VERSION_KEY} (#{requested_json_schema_version}) must be a positive integer.")
        end

        selected_json_schema_version = closest_available_json_schema_version(requested_json_schema_version)

        if selected_json_schema_version.nil?
          return malformed(
            decoded_event,
            validation_target: JSON_SCHEMA_VERSION_KEY,
            message: "Failed to select json schema version. Requested version: #{requested_json_schema_version}. \
            Available json schema versions: #{@schema_artifacts.available_json_schema_versions.sort.join(", ")}"
          )
        end

        if selected_json_schema_version != requested_json_schema_version
          @logger.info({
            "message_type" => "ElasticGraphMissingJSONSchemaVersion",
            "message_id" => decoded_event["message_id"],
            "event_id" => event_id_for(decoded_event),
            "event_type" => decoded_event["type"],
            "requested_json_schema_version" => requested_json_schema_version,
            "selected_json_schema_version" => selected_json_schema_version
          })
        end

        # Because `closest_available_json_schema_version` picks the closest-matching json schema version, the incoming
        # event might not match the expected json_schema_version value in the json schema (which is a `const` field).
        # This is by design, since we're picking a schema based on best-effort, so to avoid that by-design validation error,
        # performing the envelope validation on a "patched" version of the event.
        event_with_patched_envelope = decoded_event.merge({JSON_SCHEMA_VERSION_KEY => selected_json_schema_version})

        if (error_message = validator(EVENT_ENVELOPE_JSON_SCHEMA_NAME, selected_json_schema_version).validate_with_error_message(event_with_patched_envelope))
          return malformed(decoded_event, validation_target: "event payload", message: error_message)
        end

        nil
      end

      def malformed(decoded_event, validation_target:, message:)
        ElasticGraph::Indexer::MalformedEventError.new(
          payload: decoded_event,
          event_id: event_id_for(decoded_event),
          message_id: decoded_event["message_id"],
          main_message: "Malformed #{validation_target}. #{message}"
        )
      end

      # Mirrors `EventID#to_s` for a payload whose envelope fields are not yet known to be valid.
      def event_id_for(decoded_event)
        "#{decoded_event["type"]}:#{decoded_event["id"]}@v#{decoded_event["version"]}"
      end

      # The requested version might not necessarily be available (if the publisher is deployed ahead of the indexer, or an old schema
      # version is removed prematurely, or an indexer deployment is rolled back). So the behavior is to always pick the closest-available
      # version. If there's an exact match, great. Even if not an exact match, if the incoming event payload conforms to the closest match,
      # the event can still be indexed.
      #
      # This min_by block will take the closest version in the list. If a tie occurs, the first value in the list wins. The desired
      # behavior is in the event of a tie (highly unlikely, there shouldn't be a gap in available json schema versions), the higher version
      # should be selected. So to get that behavior, the list is sorted in descending order.
      def closest_available_json_schema_version(requested_json_schema_version)
        @schema_artifacts.available_json_schema_versions.sort.reverse.min_by { |version| (requested_json_schema_version - version).abs }
      end

      def validator(type, selected_json_schema_version)
        factory = validator_factories_by_version[selected_json_schema_version] # : Support::JSONSchema::ValidatorFactory
        factory.validator_for(type)
      end

      def validator_factories_by_version
        @validator_factories_by_version ||= ::Hash.new do |hash, raw_json_schema_version|
          json_schema_version = raw_json_schema_version # : Integer
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

      # simplecov:disable -- this should not be called. Instead, it exists to guard against wrongly raising an error from this class.
      def raise(*args)
        super("`raise` was called on `JSONIngestion::IngestionAdapter`, but should not. Instead, return " \
          "`ValidationResult.invalid(...)` or a `MalformedEventError` so that we can accumulate all invalid events and allow " \
          "the valid events to still be processed.")
      end
      # simplecov:enable
    end
  end
end
