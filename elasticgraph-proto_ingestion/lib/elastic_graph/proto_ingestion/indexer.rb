# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/indexer"
require "elastic_graph/proto_ingestion/indexing_event_decoder"
require "elastic_graph/support/from_yaml_file"

module ElasticGraph
  module ProtoIngestion
    # Adds protobuf payload decoding to a format-neutral {ElasticGraph::Indexer}.
    class Indexer
      extend Support::FromYamlFile

      # @return [ElasticGraph::Indexer] the wrapped format-neutral indexer
      # @dynamic indexer
      attr_reader :indexer

      # @return [Logger]
      def logger = indexer.logger

      # @return [ElasticGraph::Indexer::Processor]
      def processor = indexer.processor

      # Builds a protobuf-aware indexer from parsed YAML configuration.
      #
      # @param parsed_yaml [Hash] parsed YAML configuration
      # @yield [Datastore::Client] optional block to customize the datastore client
      # @return [Indexer]
      def self.from_parsed_yaml(parsed_yaml, &datastore_client_customization_block)
        new(ElasticGraph::Indexer.from_parsed_yaml(parsed_yaml, &datastore_client_customization_block), config: parsed_yaml.fetch("proto_ingestion"))
      end

      # @param indexer [ElasticGraph::Indexer] the format-neutral indexer to wrap
      # @param config [Hash<String, Object>] descriptor set and transport options
      def initialize(indexer, config:)
        @indexer = indexer
        @decoder = IndexingEventDecoder.new(config: config, schema_artifacts: indexer.schema_artifacts)
      end

      # Decodes and processes one protobuf payload containing multiple indexing events.
      #
      # If any events are invalid, an exception is raised, but valid events are still written to the datastore.
      # No attempt is made to provide atomic "all or nothing" behavior.
      #
      # @param payload [String] protobuf indexing events
      # @param metadata [Hash<String, String>] transport properties for raw messages
      # @param refresh_indices [Boolean] whether to synchronously refresh affected indices (intended for tests: this is dangerous to use in production)
      # @return [void]
      def process(payload, metadata: {}, refresh_indices: false)
        processor.process(decode(payload, metadata: metadata), refresh_indices: refresh_indices)
      end

      # Decodes and processes one protobuf payload containing multiple events, returning individual failures.
      # The caller is responsible for handling the failures.
      #
      # @param payload [String] protobuf indexing events
      # @param metadata [Hash<String, String>] transport properties for raw messages
      # @param refresh_indices [Boolean] whether to synchronously refresh affected indices (intended for tests: this is dangerous to use in production)
      # @return [Array<ElasticGraph::Indexer::FailedEventError>]
      def process_returning_failures(payload, metadata: {}, refresh_indices: false)
        processor.process_returning_failures(decode(payload, metadata: metadata), refresh_indices: refresh_indices)
      end

      # Decodes one protobuf payload without processing it.
      #
      # This supports transports that must add metadata or combine several payloads before one bulk operation.
      #
      # @param payload [String] protobuf indexing events
      # @return [Array<Hash<String, Object>>] decoded indexing events
      # @param metadata [Hash<String, String>] transport properties for raw domain messages
      def decode(payload, metadata: {})
        @decoder.decode_with_metadata(payload, metadata: metadata)
      end
    end
  end
end
