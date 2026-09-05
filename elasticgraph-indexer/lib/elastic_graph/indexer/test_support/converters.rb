# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/constants"
require "elastic_graph/support/hash_util"
require "json"

module ElasticGraph
  class Indexer
    module TestSupport
      module Converters
        # Attributes that describe the event rather than the record, so they never reach the record.
        # `__json_schema_version` is the legacy name of `__schema_version`; projects generated before
        # the schema version became ingestion-format-neutral still use it.
        EVENT_ONLY_ATTRIBUTES = ["__typename", "__version", "__schema_version", "__json_schema_version"]

        # Helper method for testing and generating fake data to convert a factory record into an event
        def self.upsert_event_for(record)
          event = {
            "op" => "upsert",
            "id" => record.fetch("id"),
            "type" => record.fetch("__typename"),
            "version" => record.fetch("__version"),
            "record" => record.except(*EVENT_ONLY_ATTRIBUTES)
          }

          # The schema version is optional, so include it only when the factory supplies one.
          schema_version = record.fetch("__schema_version") { record["__json_schema_version"] }
          unless schema_version.nil?
            event[SCHEMA_VERSION_KEY] = schema_version
          end

          event
        end

        # Helper method to create an array of events given an array of records
        def self.upsert_events_for_records(records)
          records.map { |record| upsert_event_for(Support::HashUtil.stringify_keys(record)) }
        end
      end
    end
  end
end
