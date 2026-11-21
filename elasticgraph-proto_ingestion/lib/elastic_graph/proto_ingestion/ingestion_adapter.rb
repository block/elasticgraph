# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/indexer/event"
require "elastic_graph/indexer/ingestion_adapter"
require "elastic_graph/proto_ingestion/descriptors"
require "elastic_graph/proto_ingestion/record_preparer"
require "elastic_graph/proto_ingestion/record_validator"
require "elastic_graph/proto_ingestion/runtime_metadata/schema"
require "google/protobuf"

module ElasticGraph
  module ProtoIngestion
    # Validates native protobuf events and supplies a native record preparer to the shared indexing pipeline.
    # This adapter does not load or select JSON schema versions.
    class IngestionAdapter
      # Shorthand for the result type defined by the indexer's ingestion adapter interface.
      ValidationResult = Indexer::IngestionAdapter::ValidationResult
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
      # @param event [Indexer::Event] a protobuf indexing event with a validated envelope
      # @param skip_record_validation [Boolean] whether to omit semantic record validation
      # @return [Indexer::IngestionAdapter::ValidationResult] validation and normalized event
      def validate_event(event, skip_record_validation: false)
        record = event.record
        expected_name = "#{@metadata.package_name}.#{event.type}"
        unless record.is_a?(::Google::Protobuf::MessageExts) && record.class.descriptor.name == expected_name
          return invalid("record", "Expected a protobuf message of type #{expected_name}.")
        end

        type = event.type
        if Descriptors.abstract?(record.class.descriptor)
          record = Descriptors.unwrap_abstract(record)
          return invalid("record", "An abstract record must select a concrete subtype.") unless record

          type = Descriptors.type_name(record.class.descriptor, @metadata)
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

          _, ids = resolve_path(record, target.id_source)
          next if ids.all? { |id| id.to_s.strip.empty? }

          public_path, timestamps = resolve_path(record, path)
          return "record.#{public_path.join(".")} is required to select a rollover index." if timestamps.empty?
        end
        nil
      end

      def resolve_path(record, path)
        descriptor = record.class.descriptor
        currents = [record] # : ::Array[untyped]
        public_path = path.split(".").map do |part|
          if (oneof = descriptor.lookup_oneof("value"))
            concrete = currents.filter_map { |item| Descriptors.unwrap_abstract(item) }
            if concrete.empty?
              oneof_fields = oneof.to_a # : ::Array[::Google::Protobuf::FieldDescriptor]
              descriptor = oneof_fields.fetch(0).subtype # : ::Google::Protobuf::Descriptor
            else
              descriptor = concrete.fetch(0).class.descriptor
            end
            currents = concrete
          end

          type_name = Descriptors.type_name(descriptor, @metadata)
          fields = @metadata.types_by_name[type_name]&.fields_by_name
          public_name = fields&.find { |_, meta| meta.name_in_index == part }&.first || part
          field = descriptor.lookup(public_name) # : ::Google::Protobuf::FieldDescriptor

          currents = if field.label == :repeated
            currents.flat_map { |item| item[public_name].to_a }
          else
            presence_method = :"has_#{public_name}?"
            currents.filter_map { |item| item[public_name] if item.public_send(presence_method) }
          end

          descriptor = field.subtype if field.type == :message
          public_name
        end
        [public_path, currents]
      end

      def invalid(description, error)
        ValidationResult.invalid(validation_target: description, message: error)
      end

      # simplecov:disable -- this should not be called. Instead, it exists to guard against wrongly raising an error from this class.
      def raise(*args)
        super("`raise` was called on `ProtoIngestion::IngestionAdapter`, but should not. Instead, return " \
          "`ValidationResult.invalid(...)` so that we can accumulate all invalid events and allow " \
          "the valid events to still be processed.")
      end
      # simplecov:enable
    end
  end
end
