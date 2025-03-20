# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/errors"
require "elastic_graph/indexer/event_id"

module ElasticGraph
  class Indexer
    # Indicates an event that we attempted to process which failed for some reason. It may have
    # failed due to a validation issue before we even attempted to write it to the datastore, or it
    # could have failed in the datastore itself.
    class FailedEventError < Errors::Error
      # @dynamic main_message, event, operations

      # The "main" part of the error message (without the `full_id` portion).
      attr_reader :main_message

      # The invalid event.
      attr_reader :event

      # The operations that would have been returned by the `OperationFactory` if the event was valid.
      # Note that sometimes an event is so malformed that we can't build any operations for it, but
      # most of the time we can.
      attr_reader :operations

      def self.from_failed_operation_result(result, all_operations_for_event)
        new(
          event: result.event,
          operations: all_operations_for_event,
          main_message: result.summary
        )
      end

      def initialize(event:, operations:, main_message:)
        @main_message = main_message
        @event = event
        @operations = operations

        super("#{full_id}: #{main_message}")
      end

      # A filtered list of operations that have versions that can be compared against our event
      # version. Not all operation types have a version (e.g. derived indexing `Update` operations don't).
      def versioned_operations
        @versioned_operations ||= operations.select(&:versioned?)
      end

      def full_id
        event_id = EventID.from_event(event).to_s
        if (message_id = event["message_id"])
          "#{event_id} (message_id: #{message_id})"
        else
          event_id
        end
      end

      def id
        event["id"]
      end

      def op
        event["op"]
      end

      def type
        event["type"]
      end

      def version
        event["version"]
      end

      def record
        event["record"]
      end
    end
  end
end
