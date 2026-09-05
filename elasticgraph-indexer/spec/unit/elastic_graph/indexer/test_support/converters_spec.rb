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
        describe ".upsert_event_for" do
          it "can build an `upsert` operation based on a factory-produced record" do
            factory_record = {
              "id" => "1",
              "__version" => 1,
              "__typename" => "Widget",
              "__schema_version" => 1,
              "field1" => "value1",
              "field2" => "value2"
            }

            expect(TestSupport::Converters.upsert_event_for(factory_record)).to eq(
              "op" => "upsert",
              "id" => "1",
              "version" => 1,
              "type" => "Widget",
              "record" => {"id" => "1", "field1" => "value1", "field2" => "value2"},
              SCHEMA_VERSION_KEY => 1
            )
          end

          it "accepts the legacy `__json_schema_version` attribute, so factories from older projects keep working" do
            factory_record = {
              "id" => "1",
              "__version" => 1,
              "__typename" => "Widget",
              "__json_schema_version" => 3,
              "field1" => "value1"
            }

            expect(TestSupport::Converters.upsert_event_for(factory_record)).to eq(
              "op" => "upsert",
              "id" => "1",
              "version" => 1,
              "type" => "Widget",
              "record" => {"id" => "1", "field1" => "value1"},
              SCHEMA_VERSION_KEY => 3
            )
          end

          it "preserves invalid versions for validation and gives the generic key precedence" do
            record = {"id" => "1", "__version" => 1, "__typename" => "Widget", "__schema_version" => false, "__json_schema_version" => 3}

            event = TestSupport::Converters.upsert_event_for(record)

            expect(event.fetch(SCHEMA_VERSION_KEY)).to be false
            expect(event.fetch("record")).to eq("id" => "1")
          end

          it "omits the schema version when the factory record supplies none, since the key is optional" do
            factory_record = {
              "id" => "1",
              "__version" => 1,
              "__typename" => "Widget",
              "field1" => "value1"
            }

            expect(TestSupport::Converters.upsert_event_for(factory_record)).to eq(
              "op" => "upsert",
              "id" => "1",
              "version" => 1,
              "type" => "Widget",
              "record" => {"id" => "1", "field1" => "value1"}
            )
          end
        end

        describe ".upsert_events_for_records" do
          it "converts an array of factory-produced records into an array of operations for upserting" do
            record1 = {
              "id" => "1",
              "__typename" => "Widget",
              "__version" => 1,
              "__schema_version" => 1,
              "field1" => "value1",
              "field2" => "value2"
            }

            record2 = {
              "id" => "2",
              "__typename" => "Address",
              "__version" => 5,
              "__schema_version" => 1,
              "field3" => "value5"
            }

            event = TestSupport::Converters.upsert_events_for_records([record1, record2])

            expect(event).to eq([
              {
                "op" => "upsert",
                "id" => "1",
                "version" => 1,
                "type" => "Widget",
                "record" => {"id" => "1", "field1" => "value1", "field2" => "value2"},
                SCHEMA_VERSION_KEY => 1
              },
              {
                "op" => "upsert",
                "id" => "2",
                "version" => 5,
                "type" => "Address",
                "record" => {"id" => "2", "field3" => "value5"},
                SCHEMA_VERSION_KEY => 1
              }
            ])
          end
        end
      end
    end
  end
end
