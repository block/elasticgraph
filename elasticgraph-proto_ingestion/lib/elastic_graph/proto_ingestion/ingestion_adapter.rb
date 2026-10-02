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
require "elastic_graph/support/hash_util"

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
        @converter = RecordConverter.new(@schema)
        @validator = RecordValidator.new(@schema.types, @schema.time_zones)
        object_types = schema_artifacts.runtime_metadata.object_types_by_name
        @update_targets = object_types.transform_values(&:update_targets)
        @ingestible_types = object_types.filter_map { |name, type| name unless type.update_targets.empty? }
        # Indexed abstract types have no update targets of their own but still get an envelope alternative.
        @envelope_types = @ingestible_types | object_types.filter_map { |name, type| name unless type.index_definition_names.empty? }
      end

      # Validates decoded protobuf envelopes and builds typed indexing events.
      # @param decoded_events [Array<Hash<String, Object>>] decoded protobuf events
      # @return [Array(Array<ElasticGraph::Indexer::Event>, Array<ElasticGraph::Indexer::MalformedEventError>)]
      def events_from(decoded_events)
        events, failures = [], []

        decoded_events.each do |decoded_event|
          next if @schema.deleted_type?(decoded_event["type"].to_s)
          if (error = envelope_error(decoded_event))
            failures << malformed(decoded_event, error)
          else
            events << ElasticGraph::Indexer::Event.new(
              op: decoded_event.fetch("op"),
              type: @schema.public_type_name_for(@schema.proto_type_name_for(decoded_event.fetch("type"))),
              id: decoded_event.fetch("id"),
              version: decoded_event.fetch("version"),
              record: decoded_event.fetch("record"),
              schema_version: nil,
              ingestion_format: "proto",
              message_id: decoded_event["message_id"],
              latency_timestamps: decoded_event["latency_timestamps"] || {}
            )
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
          expected_name = "#{@schema.package_name}.#{@schema.proto_type_name_for(event.type)}"
          unless record.class.respond_to?(:descriptor) && record.class.descriptor.name == expected_name
            return invalid("record", "Expected a protobuf message of type #{expected_name}.")
          end
          @schema.register(record.class.descriptor)
          begin
            record = @converter.convert(event.type, record)
          rescue JSON::ParserError, Google::Protobuf::ParseError
            return invalid("record", "Invalid encoded scalar value.")
          end
        end
        return invalid("record", "An abstract record must select a concrete subtype.") unless record
        record = record.merge("id" => event.id)
        type = event.type
        type = record["__typename"] unless @ingestible_types.include?(type)
        return invalid("record", "The selected subtype is not ingestible.") unless @ingestible_types.include?(type)
        if (error = @validator.error_for(event.type, record, wire_contract_only: skip_record_validation))
          return invalid("#{event.type} record", error)
        end
        if (error = rollover_error_for(type, record))
          return invalid("#{event.type} record", error)
        end
        ValidationResult.valid(event.with(record: record, type: type), @schema.record_preparer)
      end

      private

      # Rollover timestamps select the destination index, rather than imposing GraphQL nullability.
      # A target with no derived IDs creates no operations and therefore needs no timestamp.
      def rollover_error_for(type, record)
        @update_targets.fetch(type).each do |target|
          next unless (path = target.rollover_timestamp_value_source)
          id_path = public_path_for(type, record, target.id_source, use_index_names: target.for_normal_indexing?)
          ids = Support::HashUtil.fetch_leaf_values_at_path(record, id_path) { [] }
          next unless ids.any? { |id| !id.to_s.strip.empty? }
          public_path = public_path_for(type, record, path, use_index_names: target.for_normal_indexing?)
          value = Support::HashUtil.fetch_value_at_path(record, public_path) { nil }
          return "record.#{public_path.join(".")} is required to select a rollover index." if value.nil?
        end
        nil
      end

      def public_path_for(type, record, path, use_index_names:)
        return path.split(".") unless use_index_names
        value = record # : untyped
        path.split(".").map do |part|
          metadata = @schema.types.fetch(type)
          if (subtypes = metadata["subtypes"])
            # An absent abstract parent has no typename; its declared rollover field still
            # exists on the concrete subtypes, so use one to resolve the public error path.
            metadata = @schema.types.fetch(value&.fetch("__typename") || subtypes.first)
          end
          public_name, field = metadata.fetch("fields").find { |_, entry| entry.fetch("name_in_index") == part }
          type = field.fetch("type").delete("[]!")
          value = value.is_a?(Hash) ? value[public_name] : nil
          public_name
        end
      end

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
        return event["envelope_error"] if event["envelope_error"]
        return "op must be upsert." unless event["op"] == "upsert"
        type = @schema.public_type_name_for(@schema.proto_type_name_for(event["type"].to_s))
        return "type must identify an ingestible protobuf message." unless @envelope_types.include?(type)
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
