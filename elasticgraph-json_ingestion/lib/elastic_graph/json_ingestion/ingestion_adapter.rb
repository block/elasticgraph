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
    # Ingestion adapter for events in ElasticGraph's JSON format: it validates events against the
    # JSON schema identified by the event's `schema_version`, and prepares records using that
    # version's view of the schema. Made available to the indexer by the {IndexerExtension} that
    # {SchemaDefinition::APIExtension} registers.
    #
    # The schema version is optional. An event that omits it gets the latest available JSON schema
    # version. An event may also carry the legacy `json_schema_version` key instead of
    # `schema_version`, so that publishers and in-process callers that predate the
    # ingestion-format-neutral key keep working.
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
      # presence of a schema version in the event envelope. The JSON Lines decoder maps the
      # publisher's `json_schema_version` onto the ingestion-format-neutral `schema_version` key,
      # and the legacy key counts as well.
      #
      # An event that carries no schema version is still valid JSON input, but this adapter cannot
      # tell it apart from the event of another format, so it does not claim it here. The indexer
      # routes such an event to the sole available adapter, which covers every single-format
      # deployment.
      #
      # @param event [Hash<String, Object>] an ElasticGraph indexing event
      # @return [Boolean] whether this adapter handles the event
      def handles_event?(event)
        event.key?(SCHEMA_VERSION_KEY) || event.key?(JSON_SCHEMA_VERSION_KEY)
      end

      # Validates the given event and resolves the record preparer appropriate for the event's
      # schema version.
      #
      # @param event [Hash<String, Object>] an ElasticGraph indexing event
      # @param skip_record_validation [Boolean] whether to skip record validation; the event envelope must still be validated
      # @return [Indexer::IngestionAdapter::ValidationResult] the result of validating the event
      def validate_event(event, skip_record_validation: false)
        selected_schema_version = select_schema_version(event) { |failure| return failure }

        event_with_patched_envelope = event_for_json_schema_validation(event, selected_schema_version)

        if (error_message = validator(EVENT_ENVELOPE_JSON_SCHEMA_NAME, selected_schema_version).validate_with_error_message(event_with_patched_envelope))
          return ValidationResult.invalid(payload_description: "event payload", message: error_message)
        end

        record = event.fetch("record")
        graphql_type_name = event.fetch("type")

        if !skip_record_validation && (error_message = validator(graphql_type_name, selected_schema_version).validate_with_error_message(record))
          return ValidationResult.invalid(payload_description: "#{graphql_type_name} record", message: error_message)
        end

        ValidationResult.valid(@record_preparer_factory.for_json_schema_version(selected_schema_version))
      end

      private

      # The JSON schemas expect the `json_schema_version` key, but the event carries the
      # ingestion-format-neutral `schema_version` key, so restore the JSON-specific key here. The
      # value is the selected version rather than the requested one, because the envelope schema
      # declares `json_schema_version` as a `const`, and `select_schema_version` selects the
      # closest available version by design. This also supplies the key for an event that omitted
      # its version, since the envelope schema requires the key.
      def event_for_json_schema_validation(event, selected_schema_version)
        event
          .except(SCHEMA_VERSION_KEY, JSON_SCHEMA_VERSION_KEY)
          .merge(JSON_SCHEMA_VERSION_KEY => selected_schema_version)
      end

      # Reads the version the event requests. The ingestion-format-neutral `schema_version` key wins,
      # and the legacy JSON-specific `json_schema_version` key acts as a fallback. A `nil` result
      # means the event requests no particular version.
      def requested_schema_version_for(event)
        event[SCHEMA_VERSION_KEY] || event[JSON_SCHEMA_VERSION_KEY]
      end

      def select_schema_version(event)
        available_schema_versions = available_schema_versions_descending
        requested_schema_version = requested_schema_version_for(event)

        if requested_schema_version.nil?
          # The schema version is optional, so an event may omit it. Use the latest available version,
          # which is the first entry of the descending list. The event still gets validated against
          # that version's JSON schemas, so a malformed event still fails.
          selected_schema_version = available_schema_versions.first
        else
          # Check that a valid value has been requested (a positive integer).
          unless requested_schema_version.is_a?(Integer) && requested_schema_version >= 1
            yield ValidationResult.invalid(
              payload_description: SCHEMA_VERSION_KEY,
              message: "#{SCHEMA_VERSION_KEY} (#{requested_schema_version}) must be a positive integer."
            )
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
          selected_schema_version = available_schema_versions.min_by { |version| (requested_schema_version - version).abs }

          if selected_schema_version != requested_schema_version
            @logger.info({
              "message_type" => "ElasticGraphMissingJSONSchemaVersion",
              "message_id" => event["message_id"],
              "event_id" => Indexer::EventID.from_event(event),
              "event_type" => event["type"],
              # These fields keep their JSON-specific names to match the JSON-specific message type,
              # so that dashboards and monitors that watch them keep working.
              "requested_json_schema_version" => requested_schema_version,
              "selected_json_schema_version" => selected_schema_version
            })
          end
        end

        if selected_schema_version.nil?
          yield ValidationResult.invalid(
            payload_description: SCHEMA_VERSION_KEY,
            message: "Failed to select schema version. Requested version: #{requested_schema_version.inspect}. \
            Available schema versions: #{available_schema_versions.sort.join(", ")}"
          )
        end

        selected_schema_version
      end

      # The available versions, sorted once in descending order. Sorting here rather than per event
      # avoids repeated work, and the descending order gives `min_by` the tie-break behavior it
      # needs: on a tie, the higher version wins.
      def available_schema_versions_descending
        @available_schema_versions_descending ||= @schema_artifacts.available_json_schema_versions.sort.reverse
      end

      def validator(type, selected_schema_version)
        factory = validator_factories_by_version[selected_schema_version] # : Support::JSONSchema::ValidatorFactory
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
        super("`raise` was called on `JSONIngestion::IngestionAdapter`, but should not. Instead, use " \
          "`yield ValidationResult.invalid(...)` so that we can accumulate all invalid events and allow " \
          "the valid events to still be processed.")
      end
      # simplecov:enable
    end
  end
end
