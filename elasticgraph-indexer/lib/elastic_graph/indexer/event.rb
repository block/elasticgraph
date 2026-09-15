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
    EMPTY_LATENCY_TIMESTAMPS = {} # : Hash[String, String]
    private_constant :EMPTY_LATENCY_TIMESTAMPS

    # A decoded indexing event. This gives the format-neutral indexing pipeline named envelope
    # fields while preserving the format-specific source for adapter validation. Hash-based
    # decoders can use {.from_hash}; other decoders can construct an event directly from their
    # native representation. Field values remain unvalidated until an ingestion adapter accepts
    # the event.
    Event = ::Data.define(
      :op,
      :type,
      :id,
      :version,
      :record,
      :ingestion_format,
      :message_id,
      :latency_timestamps,
      :source
    ) do
      # @implements Event

      # @param op [String, nil] the requested operation (e.g. "upsert")
      # @param type [String, nil] the GraphQL type of the record
      # @param id [String, nil] the record identifier
      # @param version [Integer, nil] the event version
      # @param record [Object, nil] the record supplied by the publisher
      # @param ingestion_format [String] the ingestion format tag
      # @param message_id [String, nil] the transport message identifier
      # @param latency_timestamps [Hash<String, String>] timestamps used to measure indexing latency
      # @param source [Object, nil] the decoded, format-specific source used for adapter validation
      def initialize(
        op:,
        type:,
        id:,
        version:,
        record:,
        ingestion_format: "json",
        message_id: nil,
        latency_timestamps: EMPTY_LATENCY_TIMESTAMPS,
        source: nil
      )
        super
      end

      # Builds an event from a decoded string-keyed hash.
      #
      # @param payload [Hash<String, Object>] a decoded event payload
      # @return [Event]
      def self.from_hash(payload)
        new(
          op: payload["op"],
          type: payload["type"],
          id: payload["id"],
          version: payload["version"],
          record: payload["record"],
          ingestion_format: payload[INGESTION_FORMAT_KEY] || "json",
          message_id: payload["message_id"],
          latency_timestamps: payload["latency_timestamps"] || {},
          source: payload
        )
      end

      # Returns a copy with the given fields replaced. When the source is a hash, its corresponding
      # fields are also replaced so format-specific validation sees the same values.
      #
      # @return [Event]
      def with(**changes)
        attributes = self.class.members.to_h { |member| [member, public_send(member)] }
        attributes = attributes.merge(changes)
        updated_source = if source.is_a?(::Hash)
          source.merge(changes.to_h { |member, value| [member.to_s, value] })
        else
          source
        end

        self.class.new(
          op: attributes.fetch(:op),
          type: attributes.fetch(:type),
          id: attributes.fetch(:id),
          version: attributes.fetch(:version),
          record: attributes.fetch(:record),
          ingestion_format: attributes.fetch(:ingestion_format),
          message_id: attributes.fetch(:message_id),
          latency_timestamps: attributes.fetch(:latency_timestamps),
          source: updated_source
        )
      end

      # Returns the hash representation used by hash-based adapters and datastore scripts.
      #
      # @return [Hash<String, Object>]
      def to_h
        return source if source.is_a?(::Hash)

        {
          "op" => op,
          "type" => type,
          "id" => id,
          "version" => version,
          "record" => record,
          INGESTION_FORMAT_KEY => ingestion_format,
          "message_id" => message_id,
          "latency_timestamps" => latency_timestamps
        }.compact
      end

      # Compares event values without treating validation state as part of their identity.
      #
      # @param other [Object] another value
      # @return [Boolean]
      def ==(other)
        (other.is_a?(Event) || other.is_a?(Event::Validated)) &&
          Event.members.all? { |member| public_send(member) == other.public_send(member) }
      end
      alias_method :eql?, :==

      # Returns a hash based on event values without including validation state.
      #
      # @return [Integer]
      def hash
        Event.members.map { |member| public_send(member) }.hash
      end
    end

    # An event whose adapter has validated its required envelope fields. Shared indexing code
    # uses this subtype after the adapter boundary so required values have concrete types.
    Event::Validated = ::Data.define(*Event.members) do
      # @implements Event::Validated

      # Builds a validated view of an event after its adapter has accepted the envelope.
      #
      # @param event [Event] the adapter-validated event
      # @return [Validated]
      def self.from(event)
        op = event.op # : String
        type = event.type # : String
        id = event.id # : String
        version = event.version # : Integer
        ingestion_format = event.ingestion_format # : String
        message_id = event.message_id # : String?
        latency_timestamps = event.latency_timestamps # : Hash[String, String]

        new(
          op: op,
          type: type,
          id: id,
          version: version,
          record: event.record,
          ingestion_format: ingestion_format,
          message_id: message_id,
          latency_timestamps: latency_timestamps,
          source: event.source
        )
      end

      # Returns the hash representation used by hash-based adapters and datastore scripts.
      #
      # @return [Hash<String, Object>]
      def to_h
        return source if source.is_a?(::Hash)

        {
          "op" => op,
          "type" => type,
          "id" => id,
          "version" => version,
          "record" => record,
          INGESTION_FORMAT_KEY => ingestion_format,
          "message_id" => message_id,
          "latency_timestamps" => latency_timestamps
        }.compact
      end

      # Compares event values without treating validation state as part of their identity.
      #
      # @param other [Object] another value
      # @return [Boolean]
      def ==(other)
        (other.is_a?(Event) || other.is_a?(Event::Validated)) &&
          Event.members.all? { |member| public_send(member) == other.public_send(member) }
      end
      alias_method :eql?, :==

      # Returns a hash based on event values without including validation state.
      #
      # @return [Integer]
      def hash
        Event.members.map { |member| public_send(member) }.hash
      end
    end

    # Steep expects the methods implemented by the main `Indexer` file on each reopened class body.
    # @dynamic initialize, config, datastore_core, schema_artifacts, datastore_router, monotonic_clock
    # @dynamic processor, operation_factory, ingestion_adapters_by_format, logger
    # @dynamic self.from_parsed_yaml
  end
end
