# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/errors"

module ElasticGraph
  class Indexer
    # A unique identifier for an event ingested by the indexer. As a string, takes the form of
    # "[type]:[id]@v[version]", such as "Widget:123abc@v7". This format was designed to make it
    # easy to put these ids in a comma-separated list.
    EventID = ::Data.define(:type, :id, :version) do
      # @implements EventID

      # Builds an id from a decoded payload whose envelope is not yet known to be valid, so no
      # {Event} exists for it. Use {Event#event_id} for a validated event.
      #
      # @param hash [Hash<String, Object>] a decoded indexing payload
      # @return [EventID]
      def self.from_decoded_hash(hash)
        new(type: hash["type"], id: hash["id"], version: hash["version"])
      end

      def to_s
        "#{type}:#{id}@v#{version}"
      end
    end

    # Steep weirdly expects them here...
    # @dynamic initialize, config, datastore_core, schema_artifacts, datastore_router, monotonic_clock
    # @dynamic processor, operation_factory, ingestion_adapters_by_format, logger
    # @dynamic self.from_parsed_yaml
  end
end
