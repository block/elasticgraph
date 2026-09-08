# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/constants"
require "elastic_graph/indexer/ingestion_adapter"
require "elastic_graph/proto_ingestion/record_converter"
require "elastic_graph/proto_ingestion/record_validator"
require "elastic_graph/proto_ingestion/runtime_schema"

module ElasticGraph
  module ProtoIngestion
    # Validates protobuf events and supplies field metadata to the shared indexing pipeline.
    # This adapter does not load or select JSON schema versions.
    class IngestionAdapter
      # @param schema_artifacts [SchemaArtifacts::FromDisk] generated schema artifacts
      # @param logger [Logger] indexing logger
      def initialize(schema_artifacts:, logger:)
        @schema = RuntimeSchema.new(schema_artifacts)
        @converter = RecordConverter.new(@schema.types)
        @validator = RecordValidator.new(@schema.types)
        @ingestible_types = schema_artifacts.runtime_metadata.object_types_by_name.filter_map { |name, type| name unless type.update_targets.empty? }
      end

      # @return [Boolean] whether the event explicitly selects protobuf ingestion
      def handles_event?(event)
        event[INGESTION_FORMAT_KEY] == "proto"
      end

      # Validates the envelope even when record validation is sampled out.
      # @param event [Hash<String, Object>] decoded event or an event containing a protobuf message
      # @param skip_record_validation [Boolean] whether to omit semantic record validation
      # @return [Indexer::IngestionAdapter::ValidationResult] validation and normalized event
      def validate_event(event, skip_record_validation: false)
        if (error = envelope_error(event))
          return invalid("event payload", error)
        end
        record = event.fetch("record")
        unless record.is_a?(Hash)
          expected_name = "#{@schema.package_name}.#{event.fetch("type")}"
          unless record.class.respond_to?(:descriptor) && record.class.descriptor.name == expected_name
            return invalid("record", "Expected a protobuf message of type #{expected_name}.")
          end
          begin
            record = @converter.convert(event.fetch("type"), record)
          rescue JSON::ParserError, Google::Protobuf::ParseError
            return invalid("record", "Invalid encoded scalar value.")
          end
        end
        record = record.merge("id" => event.fetch("id"))
        if !skip_record_validation && (error = @validator.error_for(event.fetch("type"), record))
          return invalid("#{event.fetch("type")} record", error)
        end
        Indexer::IngestionAdapter::ValidationResult.valid(@schema.record_preparer,
          event: event.except(SCHEMA_VERSION_KEY, JSON_SCHEMA_VERSION_KEY).merge("record" => record))
      end

      private

      def invalid(description, error)
        Indexer::IngestionAdapter::ValidationResult.invalid(payload_description: description, message: error)
      end

      def envelope_error(event)
        return "op must be upsert." unless event["op"] == "upsert"
        return "type must identify an ingestible protobuf message." unless @ingestible_types.include?(event["type"])
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
