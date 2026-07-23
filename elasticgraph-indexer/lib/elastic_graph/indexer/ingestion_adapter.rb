# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  class Indexer
    # Namespace for ingestion adapters. An ingestion adapter teaches the indexer how to handle
    # events of a particular ingestion format: it validates each event and provides the
    # version-appropriate machinery to prepare the event's record for indexing.
    module IngestionAdapter
      # Defines the ingestion adapter interface. Adapter classes are not required to subclass this,
      # but must implement these methods.
      class Interface
        # @param schema_artifacts [SchemaArtifacts::FromDisk] the schema artifacts
        # @param logger [Logger] the ElasticGraph logger
        def initialize(schema_artifacts:, logger:)
          # must be defined, but nothing to do
        end

        # Indicates whether this adapter recognizes the given event as one of its own. When multiple
        # adapters are available, the indexer routes each event to the first adapter that returns
        # `true`. (When exactly one adapter is available, it receives all events.)
        #
        # @param event [Hash<String, Object>] an ElasticGraph indexing event
        # @return [Boolean] whether this adapter handles the event
        def handles_event?(event)
          # :nocov: -- must return a boolean to satisfy Steep type checking but never called
          false
          # :nocov:
        end

        # Validates the given event and resolves the record preparer appropriate for the event's
        # schema version.
        #
        # @param event [Hash<String, Object>] an ElasticGraph indexing event
        # @return [ValidationResult] the result of validating the event
        def validate_event(event)
          # :nocov: -- must return a result to satisfy Steep type checking but never called
          ValidationResult.valid(RecordPreparer::Identity)
          # :nocov:
        end
      end

      # Describes a validation problem with an event.
      #
      # @!attribute [r] payload_description
      #   @return [String] brief description of the part of the event that was invalid
      # @!attribute [r] message
      #   @return [String] detailed validation failure message
      Failure = ::Data.define(:payload_description, :message)

      # Returned by {Interface#validate_event}. Either `failure` is non-nil (the event was invalid)
      # or `record_preparer` is non-nil (the event was valid and its record can be prepared for
      # indexing with the given preparer).
      #
      # @!attribute [r] record_preparer
      #   @return [Object, nil] preparer for the event's record, when the event is valid
      # @!attribute [r] failure
      #   @return [Failure, nil] description of the validation problem, when the event is invalid
      ValidationResult = ::Data.define(:record_preparer, :failure) do
        # @implements ValidationResult

        # Builds a result for a valid event.
        #
        # @param record_preparer [Object] preparer for the event's record
        # @return [ValidationResult]
        def self.valid(record_preparer)
          new(record_preparer: record_preparer, failure: nil)
        end

        # Builds a result for an invalid event.
        #
        # @param payload_description [String] brief description of the part of the event that was invalid
        # @param message [String] detailed validation failure message
        # @return [ValidationResult]
        def self.invalid(payload_description:, message:)
          new(record_preparer: nil, failure: Failure.new(payload_description: payload_description, message: message))
        end
      end
    end
  end
end
