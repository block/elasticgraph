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
require "elastic_graph/indexer/ingestion_adapter"
require "elastic_graph/indexer/malformed_event_error"
require "elastic_graph/proto_ingestion/record_converter"
require "elastic_graph/proto_ingestion/record_validator"
require "elastic_graph/proto_ingestion/runtime_schema"

module ElasticGraph
  module ProtoIngestion
    # Validates protobuf events and supplies field metadata to the shared indexing pipeline.
    # This adapter does not load or select JSON schema versions.
    class IngestionAdapter
      ValidationResult = ElasticGraph::Indexer::IngestionAdapter::ValidationResult
      private_constant :ValidationResult

      # @param schema_artifacts [SchemaArtifacts::FromDisk] generated schema artifacts
      def initialize(schema_artifacts:)
        @schema = RuntimeSchema.new(schema_artifacts)
        @converter = RecordConverter.new(@schema.types)
        @validator = RecordValidator.new(@schema.types)
        @ingestible_types = schema_artifacts.runtime_metadata.object_types_by_name.filter_map { |name, type| name unless type.update_targets.empty? }
        @envelope_types = @ingestible_types + @schema.types.filter_map do |name, metadata|
          name if metadata["subtypes"]&.intersect?(@ingestible_types)
        end
      end

      # Validates decoded protobuf envelopes and builds typed indexing events.
      # @param decoded_events [Array<Hash<String, Object>>] decoded protobuf events
      # @return [Array(Array<ElasticGraph::Indexer::Event>, Array<ElasticGraph::Indexer::MalformedEventError>)]
      def events_from(decoded_events)
        events, failures = [], []

        decoded_events.each do |decoded_event|
          if (error = envelope_error(decoded_event))
            failures << malformed(decoded_event, error)
          else
            events << ElasticGraph::Indexer::Event.from_validated_hash(decoded_event)
          end
        end

        [events, failures]
      end

      # Converts and validates the record even when record validation is sampled out.
      # @param event [ElasticGraph::Indexer::Event] a protobuf indexing event with a validated envelope
      # @param skip_record_validation [Boolean] whether to omit semantic record validation
      # @return [::ElasticGraph::Indexer::IngestionAdapter::ValidationResult] validation and normalized event
      def validate_event(event, skip_record_validation: false)
        record = event.record
        unless record.is_a?(Hash)
          expected_name = "#{@schema.package_name}.#{event.type}"
          unless record.class.respond_to?(:descriptor) && record.class.descriptor.name == expected_name
            return invalid("record", "Expected a protobuf message of type #{expected_name}.")
          end
          begin
            record = @converter.convert(event.type, record)
          rescue JSON::ParserError, Google::Protobuf::ParseError
            return invalid("record", "Invalid encoded scalar value.")
          end
        end
        return invalid("record", "An abstract record must select a concrete subtype.") unless record
        record = record.merge("id" => event.id)
        if !skip_record_validation && (error = @validator.error_for(event.type, record))
          return invalid("#{event.type} record", error)
        end
        type = event.type
        type = record["__typename"] unless @ingestible_types.include?(type)
        return invalid("record", "The selected subtype is not ingestible.") unless @ingestible_types.include?(type)
        ValidationResult.valid(event.with(record: record, type: type), @schema.record_preparer)
      end

      private

      def invalid(description, error)
        ValidationResult.invalid(validation_target: description, message: error)
      end

      def malformed(decoded_event, error)
        ElasticGraph::Indexer::MalformedEventError.new(
          payload: decoded_event,
          event_id: ElasticGraph::Indexer::EventID.from_decoded_hash(decoded_event).to_s,
          message_id: decoded_event["message_id"],
          main_message: "Malformed event payload. #{error}"
        )
      end

      def envelope_error(event)
        return "op must be upsert." unless event["op"] == "upsert"
        return "type must identify an ingestible protobuf message." unless @envelope_types.include?(event["type"])
        return "id must be a nonempty string." unless event["id"].is_a?(String) && !event["id"].empty?
        version = event["version"]
        return "version must be a positive integer within the datastore version range." unless version.is_a?(Integer) && (1..LONG_STRING_MAX).cover?(version)
        return "record is required." if event["record"].nil?
        timestamps = event["latency_timestamps"]
        if timestamps && (!timestamps.is_a?(Hash) || !timestamps.all? { |name, value| name.is_a?(String) && RecordValidator.valid_timestamp?(value) })
          return "latency_timestamps must map names to valid ISO 8601 timestamps."
        end
        nil
      end
    end
  end
end
