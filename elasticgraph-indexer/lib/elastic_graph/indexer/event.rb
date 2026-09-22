# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/constants"
require "elastic_graph/indexer/event_id"

module ElasticGraph
  class Indexer
    # An indexing event with a validated envelope. Ingestion adapters build events after they
    # validate the envelope in their own format, so every `Event` instance has typed envelope
    # fields. `record` keeps the adapter's native record type (a `Hash` for JSON events).
    #
    # @!attribute [r] op
    #   @return [String] the operation to apply (`upsert`)
    # @!attribute [r] type
    #   @return [String] the GraphQL type of the record
    # @!attribute [r] id
    #   @return [String] the unique identifier of the record
    # @!attribute [r] version
    #   @return [Integer] version used to order events for the same `type` and `id`
    # @!attribute [r] record
    #   @return [Object] the record payload, in the ingestion adapter's native type
    # @!attribute [r] schema_version
    #   @return [Integer] the version of the ingestion schema the publisher used
    # @!attribute [r] ingestion_format
    #   @return [String] the format tag that selects the ingestion adapter
    # @!attribute [r] message_id
    #   @return [String, nil] the id of the transport message that carried the event
    # @!attribute [r] latency_timestamps
    #   @return [Hash<String, String>] ISO8601 timestamps from which indexing latency is measured
    Event = ::Data.define(:op, :type, :id, :version, :record, :schema_version, :ingestion_format, :message_id, :latency_timestamps) do
      # @implements Event[R]

      def initialize(op:, type:, id:, version:, record:, schema_version:, ingestion_format:, message_id: nil, latency_timestamps: {})
        super
      end

      # @return [EventID] identifies this event by its `type`, `id`, and `version`
      def event_id
        EventID.new(type: type, id: id, version: version)
      end

      # Builds an event from a JSON event hash whose envelope has already been validated.
      #
      # @param hash [Hash<String, Object>] a validated JSON event
      # @return [Event]
      def self.from_validated_hash(hash)
        latency_timestamps = hash["latency_timestamps"] || {} # : ::Hash[::String, ::String]

        new(
          op: hash.fetch("op"),
          type: hash.fetch("type"),
          id: hash.fetch("id"),
          version: hash.fetch("version"),
          record: hash.fetch("record"),
          schema_version: hash.fetch(JSON_SCHEMA_VERSION_KEY),
          ingestion_format: hash.fetch(INGESTION_FORMAT_KEY, "json"),
          message_id: hash["message_id"],
          latency_timestamps: latency_timestamps
        )
      end
    end

    # Steep weirdly expects them here...
    # @dynamic initialize, config, datastore_core, schema_artifacts, datastore_router, monotonic_clock
    # @dynamic processor, operation_factory, ingestion_adapters_by_format, logger
    # @dynamic self.from_parsed_yaml
  end
end
