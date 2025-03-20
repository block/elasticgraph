# Copyright 2024 - 2025 Block, Inc.
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
              "__json_schema_version" => 1,
              "field1" => "value1",
              "field2" => "value2"
            }

            expect(TestSupport::Converters.upsert_event_for(factory_record)).to eq(
              "op" => "upsert",
              "id" => "1",
              "version" => 1,
              "type" => "Widget",
              "record" => {"id" => "1", "field1" => "value1", "field2" => "value2"},
              JSON_SCHEMA_VERSION_KEY => 1
            )
          end
        end

        describe ".upsert_events_for_records" do
          it "converts an array of factory-produced records into an array of operations for upserting" do
            record1 = {
              "id" => "1",
              "__typename" => "Widget",
              "__version" => 1,
              "__json_schema_version" => 1,
              "field1" => "value1",
              "field2" => "value2"
            }

            record2 = {
              "id" => "2",
              "__typename" => "Address",
              "__version" => 5,
              "__json_schema_version" => 1,
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
                JSON_SCHEMA_VERSION_KEY => 1
              },
              {
                "op" => "upsert",
                "id" => "2",
                "version" => 5,
                "type" => "Address",
                "record" => {"id" => "2", "field3" => "value5"},
                JSON_SCHEMA_VERSION_KEY => 1
              }
            ])
          end
        end
      end
    end
  end
end
