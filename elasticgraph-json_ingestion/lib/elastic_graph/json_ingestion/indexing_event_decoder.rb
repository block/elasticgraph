# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "json"

module ElasticGraph
  module JSONIngestion
    # An indexing event decoder for payloads encoded as newline-delimited JSON objects
    # ([JSON Lines](https://jsonlines.org/)). Configure it via the `indexer.indexing_event_decoder`
    # setting of `elasticgraph-indexer`.
    class IndexingEventDecoder
      # @param config [Hash<String, Object>] configuration from the `indexing_event_decoder.config` setting
      # @param schema_artifacts [SchemaArtifacts::FromDisk] the schema artifacts
      # @param logger [Logger] the ElasticGraph logger
      def initialize(config:, schema_artifacts:, logger:)
        # must be defined for extension interface verification, but nothing to do
      end

      # @param payload [String] a raw payload from the transport
      # @return [Array<Hash<String, Object>>] the decoded ElasticGraph indexing events
      def decode(payload)
        payload.split("\n").map { |event| JSON.parse(event) }
      end
    end
  end
end
