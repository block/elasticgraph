# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  class Indexer
    # Namespace for indexing event decoders, which turn raw payload strings from a transport into
    # ElasticGraph indexing event hashes. The decoder to use is configured via the
    # `indexer.indexing_event_decoder` setting.
    module IndexingEventDecoder
      # Defines the indexing event decoder interface, which our extension loader will validate against.
      class Interface
        # @param config [Hash<String, Object>] configuration from the `indexing_event_decoder.config` setting
        # @param schema_artifacts [SchemaArtifacts::FromDisk] the schema artifacts
        # @param logger [Logger] the ElasticGraph logger
        def initialize(config:, schema_artifacts:, logger:)
          # must be defined, but nothing to do
        end

        # @param payload [String] a raw payload from the transport
        # @return [Array<Hash<String, Object>>] the decoded ElasticGraph indexing events
        def decode(payload)
          # :nocov: -- must return an array to satisfy Steep type checking but never called
          []
          # :nocov:
        end
      end
    end
  end
end
