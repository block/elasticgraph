# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/constants"
require "elastic_graph/indexer/event"
require "elastic_graph/indexer/event_id"
require "elastic_graph/indexer/malformed_event_error"
require "elastic_graph/support/json_schema/validator_factory"

module ElasticGraph
  module JSONIngestion
    # Turns decoded JSON payloads into indexing events, rejecting any whose envelope is malformed.
    # Also owns the versioned JSON schema validators, which {IngestionAdapter} uses for record
    # validation.
    class EnvelopeValidator
      # @param schema_artifacts [SchemaArtifacts::FromDisk] the schema artifacts
      # @param logger [Logger] the ElasticGraph logger
      # @param configure_record_validator [Proc, nil] optional callback to further configure the record validator
      def initialize(schema_artifacts:, logger:, configure_record_validator: nil)
        @schema_artifacts = schema_artifacts.extension_artifacts.fetch("json")
        @logger = logger
        @configure_record_validator = configure_record_validator
      end

      # Validates the envelope of each decoded JSON event and builds an {ElasticGraph::Indexer::Event}
      # for each valid one.
      #
      # @param decoded_events [Array<Hash<String, Object>>] decoded JSON indexing events
      # @return [Array(Array<ElasticGraph::Indexer::Event>, Array<ElasticGraph::Indexer::MalformedEventError>)]
      #   the events with a valid envelope, and a failure for each event with a malformed envelope
      def events_from(decoded_events)
        events, failures = [], []

        decoded_events.each do |decoded_event|
          if (failure = envelope_failure_for(decoded_event))
            failures << failure
          else
            events << event_from(decoded_event)
          end
        end

        [events, failures]
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
      # @param requested_json_schema_version [Integer] the version the event asked for
      # @return [Integer, nil] the closest available version, or nil when none is available
      def closest_available_json_schema_version(requested_json_schema_version)
        @schema_artifacts.available_json_schema_versions.sort.reverse.min_by { |version| (requested_json_schema_version - version).abs }
      end

      # @param type [String] name of the type (or the event envelope) to validate
      # @param selected_json_schema_version [Integer] the JSON schema version to validate against
      # @return [ElasticGraph::Support::JSONSchema::Validator]
      def validator(type, selected_json_schema_version)
        factory = validator_factories_by_version[selected_json_schema_version] # : Support::JSONSchema::ValidatorFactory
        factory.validator_for(type)
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
            "event_id" => ElasticGraph::Indexer::EventID.from_decoded_hash(decoded_event),
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
          event_id: ElasticGraph::Indexer::EventID.from_decoded_hash(decoded_event).to_s,
          message_id: decoded_event["message_id"],
          main_message: "Malformed #{validation_target}. #{message}"
        )
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
        super("`raise` was called on `JSONIngestion::EnvelopeValidator`, but should not. Instead, return a " \
          "`MalformedEventError` so that we can accumulate all malformed events and allow the valid events " \
          "to still be processed.")
      end
      # simplecov:enable
    end
  end
end
