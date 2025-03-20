# Copyright 2024 - 2025 Block, Inc.
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
        # Helper method for testing and generating fake data to convert a factory record into an event
        def self.upsert_event_for(record)
          {
            "op" => "upsert",
            "id" => record.fetch("id"),
            "type" => record.fetch("__typename"),
            "version" => record.fetch("__version"),
            "record" => record.except("__typename", "__version", "__json_schema_version"),
            JSON_SCHEMA_VERSION_KEY => record.fetch("__json_schema_version")
          }
        end

        # Helper method to create an array of events given an array of records
        def self.upsert_events_for_records(records)
          records.map { |record| upsert_event_for(Support::HashUtil.stringify_keys(record)) }
        end
      end
    end
  end
end
