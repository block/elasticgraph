# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/constants"
require "elastic_graph/indexer/event"

module ElasticGraph
  class Indexer
    RSpec.describe Event do
      describe ".from_validated_hash" do
        it "builds an event from every envelope field of a JSON event hash" do
          event = Event.from_validated_hash({
            "op" => "upsert",
            "type" => "Widget",
            "id" => "w1",
            "version" => 3,
            "record" => {"id" => "w1", "name" => "Widgy"},
            JSON_SCHEMA_VERSION_KEY => 2,
            INGESTION_FORMAT_KEY => "other",
            "message_id" => "m1",
            "latency_timestamps" => {"created_at" => "2024-01-01T00:00:00Z"}
          })

          expect(event).to eq(Event.new(
            op: "upsert",
            type: "Widget",
            id: "w1",
            version: 3,
            record: {"id" => "w1", "name" => "Widgy"},
            schema_version: 2,
            ingestion_format: "other",
            message_id: "m1",
            latency_timestamps: {"created_at" => "2024-01-01T00:00:00Z"}
          ))
        end

        it "defaults the optional envelope fields when the hash omits them" do
          event = Event.from_validated_hash({
            "op" => "upsert",
            "type" => "Widget",
            "id" => "w1",
            "version" => 3,
            "record" => {"id" => "w1"},
            JSON_SCHEMA_VERSION_KEY => 1
          })

          expect(event).to eq(Event.new(
            op: "upsert",
            type: "Widget",
            id: "w1",
            version: 3,
            record: {"id" => "w1"},
            schema_version: 1,
            ingestion_format: "json",
            message_id: nil,
            latency_timestamps: {}
          ))
        end
      end
    end
  end
end
