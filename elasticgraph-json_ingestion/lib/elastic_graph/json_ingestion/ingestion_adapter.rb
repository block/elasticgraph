# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/constants"
require "elastic_graph/indexer/ingestion_adapter"
require "elastic_graph/json_ingestion/envelope_validator"
require "elastic_graph/json_ingestion/record_preparer_factory"

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

      # @return [EnvelopeValidator] validates decoded JSON payloads before operations are built from them
      # @dynamic envelope_validator
      attr_reader :envelope_validator

      # @param schema_artifacts [SchemaArtifacts::FromDisk] the schema artifacts
      # @param logger [Logger] the ElasticGraph logger
      # @param configure_record_validator [Proc, nil] optional callback to further configure the record validator
      def initialize(schema_artifacts:, logger:, configure_record_validator: nil)
        @envelope_validator = EnvelopeValidator.new(
          schema_artifacts: schema_artifacts,
          logger: logger,
          configure_record_validator: configure_record_validator
        )
        @record_preparer_factory = RecordPreparerFactory.new(schema_artifacts)
      end

      # Validates the record of the given event and resolves the record preparer appropriate for
      # the event's JSON schema version.
      #
      # @param event [ElasticGraph::Indexer::Event] an ElasticGraph indexing event
      # @param skip_record_validation [Boolean] whether to skip record validation
      # @return [ElasticGraph::Indexer::IngestionAdapter::ValidationResult] the result of validating the event
      def validate_event(event, skip_record_validation: false)
        # Envelope validation has already confirmed that a version can be selected for this event.
        schema_version = event.schema_version # : ::Integer
        selected_json_schema_version = @envelope_validator.closest_available_json_schema_version(schema_version) # : ::Integer

        # The datastore includes `id` in search payloads only when it is part of the indexed record.
        record = event.record.merge("id" => event.id)

        if !skip_record_validation && (error_message = @envelope_validator.validator(event.type, selected_json_schema_version).validate_with_error_message(record))
          return ValidationResult.invalid(validation_target: "#{event.type} record", message: error_message)
        end

        ValidationResult.valid(event.with(record: record), @record_preparer_factory.for_json_schema_version(selected_json_schema_version))
      end

      private

      # simplecov:disable -- this should not be called. Instead, it exists to guard against wrongly raising an error from this class.
      def raise(*args)
        super("`raise` was called on `JSONIngestion::IngestionAdapter`, but should not. Instead, return " \
          "`ValidationResult.invalid(...)` so that we can accumulate all invalid events and allow " \
          "the valid events to still be processed.")
      end
      # simplecov:enable
    end
  end
end
