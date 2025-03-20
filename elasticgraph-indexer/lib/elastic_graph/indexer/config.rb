# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/errors"
require "elastic_graph/indexer/event_id"

module ElasticGraph
  class Indexer
    class Config < ::Data.define(
      # Map of indexing latency thresholds (in milliseconds), keyed by the name of
      # the indexing latency metric. When an event is indexed with an indexing latency
      # exceeding the threshold, a warning with the event type, id, and version will
      # be logged, so the issue can be investigated.
      :latency_slo_thresholds_by_timestamp_in_ms,
      # Setting that can be used to specify some derived indexing type updates that should be skipped. This
      # setting should be a map keyed by the name of the derived indexing type, and the values should be sets
      # of ids. This can be useful when you have a "hot spot" of a single derived document that is
      # receiving a ton of updates. During a backfill (or whatever) you may want to skip the derived
      # type updates.
      :skip_derived_indexing_type_updates
    )
      def self.from_parsed_yaml(hash)
        hash = hash.fetch("indexer")
        extra_keys = hash.keys - EXPECTED_KEYS

        unless extra_keys.empty?
          raise Errors::ConfigError, "Unknown `indexer` config settings: #{extra_keys.join(", ")}"
        end

        new(
          latency_slo_thresholds_by_timestamp_in_ms: hash.fetch("latency_slo_thresholds_by_timestamp_in_ms"),
          skip_derived_indexing_type_updates: (hash["skip_derived_indexing_type_updates"] || {}).transform_values(&:to_set)
        )
      end

      EXPECTED_KEYS = members.map(&:to_s)
    end

    # Steep weirdly expects them here...
    # @dynamic initialize, config, datastore_core, schema_artifacts, datastore_router
    # @dynamic record_preparer, processor, operation_factory
  end
end
