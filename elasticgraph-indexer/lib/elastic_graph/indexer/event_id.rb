# Copyright 2024 - 2025 Block, Inc.
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
    # easy to put these ids in a comma-seperated list.
    EventID = ::Data.define(:type, :id, :version) do
      # @implements EventID
      def self.from_event(event)
        new(type: event["type"], id: event["id"], version: event["version"])
      end

      def to_s
        "#{type}:#{id}@v#{version}"
      end
    end

    # Steep weirdly expects them here...
    # @dynamic initialize, config, datastore_core, schema_artifacts, datastore_router, monotonic_clock
    # @dynamic record_preparer_factory, processor, operation_factory, logger
    # @dynamic self.from_parsed_yaml
  end
end
