# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/indexer/event"
require "elastic_graph/indexer/ingestion_adapter"
require "elastic_graph/proto_ingestion/record_preparer"
require "elastic_graph/proto_ingestion/record_validator"
require "elastic_graph/proto_ingestion/runtime_metadata/schema"

module ElasticGraph
  module ProtoIngestion
    # Validates native protobuf events and supplies a native record preparer to the shared indexing pipeline.
    # This adapter does not load or select JSON schema versions.
    class IngestionAdapter
      ValidationResult = ElasticGraph::Indexer::IngestionAdapter::ValidationResult
      private_constant :ValidationResult

      # @param schema_artifacts [SchemaArtifacts::FromDisk] generated schema artifacts
      def initialize(schema_artifacts:)
        @metadata = RuntimeMetadata::Schema.from_schema_artifacts(schema_artifacts)
        @record_preparer = RecordPreparer.new(schema_artifacts)
        @validator = RecordValidator.new(@metadata)
        object_types = schema_artifacts.runtime_metadata.object_types_by_name
        @update_targets = object_types.transform_values(&:update_targets)
        @ingestible_types = object_types.filter_map { |name, type| name unless type.update_targets.empty? }.to_set
      end

      # Validates the native protobuf record and prepares the event for the shared indexing pipeline.
      # @param event [ElasticGraph::Indexer::Event] a protobuf indexing event with a validated envelope
      # @param skip_record_validation [Boolean] whether to omit semantic record validation
      # @return [::ElasticGraph::Indexer::IngestionAdapter::ValidationResult] validation and normalized event
      def validate_event(event, skip_record_validation: false)
        record = event.record
        expected_name = "#{@metadata.package_name}.#{event.type}"
        unless record.class.respond_to?(:descriptor) && record.class.descriptor.name == expected_name
          return invalid("record", "Expected a protobuf message of type #{expected_name}.")
        end

        type = event.type
        if record.class.descriptor.lookup_oneof("value")
          alternative = record.value
          return invalid("record", "An abstract record must select a concrete subtype.") unless alternative
          record = record.public_send(alternative)
          type = record.class.descriptor.name.delete_prefix("#{@metadata.package_name}.")
        end

        return invalid("record", "The selected subtype is not ingestible.") unless @ingestible_types.include?(type)
        if (error = @validator.error_for(record, wire_contract_only: skip_record_validation))
          return invalid("#{event.type} record", error)
        end

        record = record.dup
        record.id = event.id
        if (error = rollover_error_for(type, record))
          return invalid("#{event.type} record", error)
        end

        ValidationResult.valid(event.with(record: record, type: type), @record_preparer)
      end

      private

      # Rollover timestamps select the destination index, rather than imposing GraphQL nullability.
      # A target with no derived IDs creates no operations and therefore needs no timestamp.
      def rollover_error_for(type, record)
        @update_targets.fetch(type).each do |target|
          next unless (path = target.rollover_timestamp_value_source)
          _, id = resolve_path(record, target.id_source)
          next if id.to_s.strip.empty?
          public_path, value = resolve_path(record, path)
          return "record.#{public_path.join(".")} is required to select a rollover index." if value.nil?
        end
        nil
      end

      def resolve_path(record, path)
        descriptor = record.class.descriptor
        current = record # : untyped
        public_path = path.split(".").map do |part|
          if (oneof = descriptor.lookup_oneof("value"))
            if (alternative = current&.value)
              current = current.public_send(alternative)
              descriptor = current.class.descriptor
            else
              oneof_fields = oneof.to_a # : Array[Google::Protobuf::FieldDescriptor]
              descriptor = oneof_fields.fetch(0).subtype # : Google::Protobuf::Descriptor
            end
          end

          type_name = descriptor.name.delete_prefix("#{@metadata.package_name}.")
          fields = @metadata.types_by_name[type_name]&.fields_by_name
          public_name = fields&.find { |_, meta| meta.name_in_index == part }&.first || part
          field = descriptor.lookup(public_name)
          current = if current&.public_send(:"has_#{public_name}?")
            current[public_name]
          end
          descriptor = field.subtype if field.type == :message
          public_name
        end
        [public_path, current]
      end

      def invalid(description, error)
        ValidationResult.invalid(validation_target: description, message: error)
      end
    end
  end
end
