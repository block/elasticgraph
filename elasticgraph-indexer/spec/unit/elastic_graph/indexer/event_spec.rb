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
          "message_id" => "m1",
          "latency_timestamps" => {"created_at" => "2026-09-11T12:00:00Z"}
        }

        event = Event.from(payload)

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
        expect(event).to eq(Event.from(payload))
        expect(Event.from(event)).to equal(event)
      end

      it "returns nil for missing envelope fields so an adapter can report all validation failures" do
        event = Event.from({})

        expect(event).to have_attributes(
          op: nil,
          type: nil,
          id: nil,
          version: nil,
          record: nil,
          ingestion_format: nil,
          message_id: nil,
          latency_timestamps: nil
        )
      end

      it "returns an event copy when replacing payload fields" do
        original = Event.from({"id" => "old", "type" => "Widget"})
        updated = original.with_payload("id" => "new")

        expect(updated.to_h).to eq("id" => "new", "type" => "Widget")
        expect(original.to_h).to eq("id" => "old", "type" => "Widget")
        expect(updated).to eql(Event.from(updated.to_h))
        expect(updated.hash).to eq(Event.from(updated.to_h).hash)
      end
    end
  end
end
