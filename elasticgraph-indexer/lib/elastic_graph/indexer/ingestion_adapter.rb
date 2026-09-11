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
        # Validates the given event and resolves the record preparer appropriate for the event's
        # ingestion schema version. The indexer selects this adapter from the event's format tag.
        #
        # @param event [Event] an ElasticGraph indexing event
        # @param skip_record_validation [Boolean] whether to skip record validation; the event envelope must still be validated
        # @return [ValidationResult] the result of validating the event
        def validate_event(event, skip_record_validation: false)
          # simplecov:disable -- must return a result to satisfy Steep type checking but never called
          ValidationResult.valid(RecordPreparer::Identity)
          # simplecov:enable
        end
      end

      # Describes a validation problem with an event.
      #
      # @!attribute [r] validation_target
      #   @return [String] brief description of the part of the event that was invalid
      # @!attribute [r] message
      #   @return [String] detailed validation failure message
      Failure = ::Data.define(:validation_target, :message)

      # Returned by {Interface#validate_event}. A non-nil `failure` indicates an invalid event,
      # and a non-nil `record_preparer` indicates a valid event.
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
        # @param validation_target [String] brief description of the part of the event that was invalid
        # @param message [String] detailed validation failure message
        # @return [ValidationResult]
        def self.invalid(validation_target:, message:)
          new(record_preparer: nil, failure: Failure.new(validation_target: validation_target, message: message))
        end
      end
    end
  end
end
