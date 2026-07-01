# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/constants"
require "json"

module ElasticGraph
  module JSONIngestion
    module IndexingEventDecoder
      # Indexing event decoder for JSON ingestion payloads represented as newline-delimited JSON objects.
      class JSONLines
        # @param config [Hash<String, Object>] configuration from the `indexing_event_decoder.config` setting
        # @param schema_artifacts [SchemaArtifacts::FromDisk] the schema artifacts
        # @param logger [Logger] the ElasticGraph logger
        def initialize(config:, schema_artifacts:, logger:)
          # must be defined for extension interface verification, but nothing to do
        end

        # @param payload [String] a raw JSON Lines payload
        # @return [Array<Hash<String, Object>>] the decoded ElasticGraph indexing events
        def decode(payload)
          payload.split("\n").map do |event_json|
            event = ::JSON.parse(event_json)
            adapt_json_schema_version(event)
          end
        end

        private

        def adapt_json_schema_version(event)
          return event unless event.key?(JSON_SCHEMA_VERSION_KEY)

          event.except(JSON_SCHEMA_VERSION_KEY).merge(SCHEMA_VERSION_KEY => event.fetch(JSON_SCHEMA_VERSION_KEY))
        end
      end
    end
  end
end
