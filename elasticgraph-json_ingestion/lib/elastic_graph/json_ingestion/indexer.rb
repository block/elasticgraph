# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/indexer"
require "elastic_graph/indexer/indexing_failures_error"
require "elastic_graph/support/from_yaml_file"
require "json"

module ElasticGraph
  module JSONIngestion
    # Adds JSON payload decoding to a format-neutral {ElasticGraph::Indexer}.
    class Indexer
      extend Support::FromYamlFile

      # @return [ElasticGraph::Indexer] the wrapped format-neutral indexer
      # @dynamic indexer
      attr_reader :indexer

      # @return [Logger]
      def logger = indexer.logger

      # @return [ElasticGraph::Indexer::Processor]
      def processor = indexer.processor

      # Builds a JSON-aware indexer from parsed YAML configuration.
      #
      # @param parsed_yaml [Hash] parsed YAML configuration
      # @yield [Datastore::Client] optional block to customize the datastore client
      # @return [Indexer]
      def self.from_parsed_yaml(parsed_yaml, &datastore_client_customization_block)
        new(ElasticGraph::Indexer.from_parsed_yaml(parsed_yaml, &datastore_client_customization_block))
      end

      # @param indexer [ElasticGraph::Indexer] the format-neutral indexer to wrap
      def initialize(indexer)
        @indexer = indexer
      end

      # Decodes and processes one JSON Lines payload containing multiple indexing events.
      #
      # If any events are invalid, an exception is raised, but valid events are still written to the datastore.
      # No attempt is made to provide atomic "all or nothing" behavior.
      #
      # @param payload [String] newline-delimited JSON indexing events
      # @param refresh_indices [Boolean] whether to synchronously refresh affected indices (intended for tests: this is dangerous to use in production)
      # @return [void]
      def process(payload, refresh_indices: false)
        decoded_events = decode(payload)
        failures = process_decoded_returning_failures(decoded_events, refresh_indices: refresh_indices)
        return if failures.empty?
        raise ElasticGraph::Indexer::IndexingFailuresError.for(failures: failures, event_count: decoded_events.size)
      end

      # Decodes and processes one JSON Lines payload containing multiple events, returning individual failures.
      # The caller is responsible for handling the failures.
      #
      # @param payload [String] newline-delimited JSON indexing events
      # @param refresh_indices [Boolean] whether to synchronously refresh affected indices (intended for tests: this is dangerous to use in production)
      # @return [Array<ElasticGraph::Indexer::FailedEventError, ElasticGraph::Indexer::MalformedEventError>]
      def process_returning_failures(payload, refresh_indices: false)
        process_decoded_returning_failures(decode(payload), refresh_indices: refresh_indices)
      end

      # Processes already-decoded events, returning individual failures. The caller is responsible
      # for handling the failures.
      #
      # This supports transports that must add metadata or combine several payloads before one bulk operation.
      #
      # @param decoded_events [Array<Hash<String, Object>>] decoded indexing events, as returned by {#decode}
      # @param refresh_indices [Boolean] whether to synchronously refresh affected indices (intended for tests: this is dangerous to use in production)
      # @return [Array<ElasticGraph::Indexer::FailedEventError, ElasticGraph::Indexer::MalformedEventError>]
      def process_decoded_returning_failures(decoded_events, refresh_indices: false)
        events, malformed_failures = ingestion_adapter.events_from(decoded_events)
        processor.process_returning_failures(events, refresh_indices: refresh_indices) + malformed_failures
      end

      # Decodes one JSON Lines payload without processing it.
      #
      # @param payload [String] newline-delimited JSON indexing events
      # @return [Array<Hash<String, Object>>] decoded indexing events
      def decode(payload)
        payload.split("\n").map { |event| ::JSON.parse(event) }
      end

      private

      def ingestion_adapter
        _ = indexer.ingestion_adapters_by_format.fetch("json")
      end
    end
  end
end
