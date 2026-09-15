# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/indexer/event"

module ElasticGraph
  class Indexer
    RSpec.describe Event do
      it "provides named access to the format-neutral event envelope" do
        payload = {
          "op" => "upsert",
          "type" => "Widget",
          "id" => "w1",
          "version" => 3,
          "record" => {"name" => "A widget"},
          INGESTION_FORMAT_KEY => "json",
          JSON_SCHEMA_VERSION_KEY => 3,
          "message_id" => "m1",
          "latency_timestamps" => {"created_at" => "2026-09-11T12:00:00Z"}
        }

        event = Event.from_hash(payload)

        expect(event).to have_attributes(
          op: "upsert",
          type: "Widget",
          id: "w1",
          version: 3,
          record: {"name" => "A widget"},
          ingestion_format: "json",
          message_id: "m1",
          latency_timestamps: {"created_at" => "2026-09-11T12:00:00Z"}
        )
        expect(event.to_h).to equal(payload)
        expect(event.source).to equal(payload)
        expect(Event.from(event)).to equal(event)
      end

      it "can be built directly from a format's native values without a hash payload" do
        record = Object.new
        source = Object.new
        event = Event.new(op: "upsert", type: "Widget", id: "w1", version: 3, record: record,
          ingestion_format: "proto", source: source)

        expect(event).to have_attributes(
          op: "upsert",
          type: "Widget",
          id: "w1",
          version: 3,
          record: record,
          ingestion_format: "proto",
          message_id: nil,
          latency_timestamps: {},
          source: source
        )
        expect(event.to_h).to eq(
          "op" => "upsert",
          "type" => "Widget",
          "id" => "w1",
          "version" => 3,
          "record" => record,
          INGESTION_FORMAT_KEY => "proto",
          "latency_timestamps" => {}
        )

        updated_record = Object.new
        expect(event.with(record: updated_record)).to have_attributes(record: updated_record, source: source)
      end

      it "returns defaults for optional fields and nil for missing required fields" do
        event = Event.from_hash({})

        expect(event).to have_attributes(
          op: nil,
          type: nil,
          id: nil,
          version: nil,
          record: nil,
          ingestion_format: "json",
          message_id: nil,
          latency_timestamps: {},
          source: {}
        )
      end

      it "returns an event copy when replacing fields" do
        original = Event.from_hash({"id" => "old", "type" => "Widget"})
        updated = original.with(id: "new")

        expect(updated.id).to eq("new")
        expect(updated.to_h).to eq("id" => "new", "type" => "Widget")
        expect(original.to_h).to eq("id" => "old", "type" => "Widget")
      end
    end
  end
end
