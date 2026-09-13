# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/indexer"
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

      # @return [ElasticGraph::Indexer::Config]
      def config = indexer.config

      # @return [DatastoreCore]
      def datastore_core = indexer.datastore_core

      # @return [Logger]
      def logger = indexer.logger

      # @return [ElasticGraph::Indexer::Processor]
      def processor = indexer.processor

      # @return [SchemaArtifacts::FromDisk]
      def schema_artifacts = indexer.schema_artifacts

      # Builds a JSON-aware indexer from parsed YAML configuration.
      #
      # @param parsed_yaml [Hash] parsed YAML configuration
      # @yield [Datastore::Client] optional block to customize the datastore client
      # @return [Indexer]
      def self.from_parsed_yaml(parsed_yaml, &datastore_client_customization_block)
        new(indexer: ElasticGraph::Indexer.from_parsed_yaml(parsed_yaml, &datastore_client_customization_block))
      end

      # @param indexer [ElasticGraph::Indexer] the format-neutral indexer to wrap
      def initialize(indexer:)
        @indexer = indexer
      end

      # Decodes and processes one JSON Lines payload.
      #
      # @param payload [String] newline-delimited JSON indexing events
      # @param refresh_indices [Boolean] whether to refresh affected indices
      # @return [void]
      def process(payload, refresh_indices: false)
        processor.process(decode(payload), refresh_indices: refresh_indices)
      end

      # Decodes and processes one JSON Lines payload, returning individual failures.
      #
      # @param payload [String] newline-delimited JSON indexing events
      # @param refresh_indices [Boolean] whether to refresh affected indices
      # @return [Array<ElasticGraph::Indexer::FailedEventError>]
      def process_returning_failures(payload, refresh_indices: false)
        processor.process_returning_failures(decode(payload), refresh_indices: refresh_indices)
      end

      # Decodes one JSON Lines payload without processing it.
      #
      # This supports transports that must add metadata or combine several payloads before one bulk operation.
      #
      # @param payload [String] newline-delimited JSON indexing events
      # @return [Array<Hash<String, Object>>] decoded indexing events
      def decode(payload)
        payload.split("\n").map { |event| JSON.parse(event) }
      end
    end
  end
end
