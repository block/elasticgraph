# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/constants"

module ElasticGraph
  class Indexer
    # A decoded indexing event. This gives the format-neutral indexing pipeline named accessors
    # for the event envelope while preserving the format-specific payload for adapter validation.
    #
    # @!attribute [r] payload
    #   @return [Hash<String, Object>] the decoded, format-specific event payload
    Event = ::Data.define(:payload) do
      # @implements Event

      # Wraps `value` as an event, leaving existing events unchanged.
      #
      # @param value [Event, Hash<String, Object>] a decoded event or its raw payload
      # @return [Event]
      def self.from(value)
        case value
        when Event
          value
        else
          new(payload: value)
        end
      end

      # @return [Object, nil] the requested operation
      def op
        payload["op"]
      end

      # @return [Object, nil] the GraphQL type of the record
      def type
        payload["type"]
      end

      # @return [Object, nil] the record identifier
      def id
        payload["id"]
      end

      # @return [Object, nil] the event version
      def version
        payload["version"]
      end

      # @return [Object, nil] the record supplied by the publisher
      def record
        payload["record"]
      end

      # @return [Object, nil] the ingestion format tag
      def ingestion_format
        payload[INGESTION_FORMAT_KEY]
      end

      # @return [Object, nil] the transport message identifier
      def message_id
        payload["message_id"]
      end

      # @return [Object, nil] timestamps used to measure indexing latency
      def latency_timestamps
        payload["latency_timestamps"]
      end

      # Returns a copy with the given payload fields replaced.
      #
      # @param fields [Hash<String, Object>] replacement payload fields
      # @return [Event]
      def with_payload(fields)
        self.class.new(payload: payload.merge(fields))
      end

      # Returns the format-specific payload for adapter validation.
      #
      # @return [Hash<String, Object>]
      def to_h
        payload
      end
    end

    # Steep expects the methods implemented by the main `Indexer` file on each reopened class body.
    # @dynamic initialize, config, datastore_core, schema_artifacts, datastore_router, monotonic_clock
    # @dynamic processor, operation_factory, ingestion_adapters_by_format, indexing_event_decoder, logger
    # @dynamic default_ingestion_adapters_by_format
    # @dynamic self.from_parsed_yaml
  end
end
