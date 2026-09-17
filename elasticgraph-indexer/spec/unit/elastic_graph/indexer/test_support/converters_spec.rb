# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/constants"
require "elastic_graph/indexer/test_support/converters"

module ElasticGraph
  class Indexer
    module TestSupport
      RSpec.describe Converters, :factories do
        let(:widget_record) do
          {
            "id" => "1",
            "__version" => 1,
            "__typename" => "Widget",
            "__json_schema_version" => 1,
            "field1" => "value1",
            "field2" => "value2"
          }
        end

        describe ".upsert_event_hash_for" do
          it "builds the JSON hash of an `upsert` event from a factory-produced record" do
            expect(Converters.upsert_event_hash_for(widget_record)).to eq(
              "op" => "upsert",
              "id" => "1",
              "version" => 1,
              "type" => "Widget",
              "record" => {"id" => "1", "field1" => "value1", "field2" => "value2"},
              JSON_SCHEMA_VERSION_KEY => 1
            )
          end
        end

        describe ".upsert_event_for" do
          it "builds an `upsert` event from a factory-produced record" do
            expect(Converters.upsert_event_for(widget_record)).to eq(Event.new(
              op: "upsert",
              id: "1",
              version: 1,
              type: "Widget",
              record: {"id" => "1", "field1" => "value1", "field2" => "value2"},
              schema_version: 1,
              ingestion_format: "json"
            ))
          end
        end

        describe ".upsert_events_for_records" do
          it "converts an array of factory-produced records, with string or symbol keys, into `upsert` events" do
            address_record = {
              id: "2",
              __typename: "Address",
              __version: 5,
              __json_schema_version: 1,
              field3: "value5"
            }

            events = Converters.upsert_events_for_records([widget_record, address_record])

            expect(events).to eq([
              Converters.upsert_event_for(widget_record),
              Event.new(
                op: "upsert",
                id: "2",
                version: 5,
                type: "Address",
                record: {"id" => "2", "field3" => "value5"},
                schema_version: 1,
                ingestion_format: "json"
              )
            ])
          end
        end
      end
    end
  end
end
