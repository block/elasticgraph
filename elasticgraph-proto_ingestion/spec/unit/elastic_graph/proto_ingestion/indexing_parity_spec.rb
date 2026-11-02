# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/proto_ingestion/ingestion_adapter"
require "elastic_graph/spec_support/proto_publisher"

module ElasticGraph
  module ProtoIngestion
    RSpec.describe "Protobuf indexing parity", :builds_indexer, :factories do
      let(:schema_artifacts) { stock_schema_artifacts }
      let(:indexer) { build_indexer(schema_artifacts: schema_artifacts) }
      let(:publisher) { SpecSupport::ProtoPublisher.new(schema_artifacts) }

      %i[component widget team address electrical_part mechanical_part].each do |factory|
        it "builds the same datastore operations for a #{factory} published as JSON or protobuf" do
          event = build_upsert_event(factory)
          json = indexer.operation_factory.build(event)
          proto_event = publisher.round_trip(event)
          proto = indexer.operation_factory.build(proto_event)

          expect(proto_event.record).not_to be_a(Hash)
          expect(proto_event.schema_version).to be_nil
          expect(json.failed_event_error).to be_nil
          expect(proto.failed_event_error).to be_nil
          expect(proto.operations.map(&:to_datastore_bulk)).to eq(json.operations.map(&:to_datastore_bulk))
        end
      end

      it "registers different record types safely when an adapter is shared by threads" do
        adapter = IngestionAdapter.new(schema_artifacts: schema_artifacts)
        events = %i[team widget component address].map { |factory| publisher.round_trip(build_upsert_event(factory)) }
        results = events.map { |event| Thread.new { adapter.validate_event(event) } }.map(&:value)
        expect(results.map(&:failure)).to all be_nil
        expect(results.map { |result| result.event.record.id }).to eq(events.map(&:id))
      end

      it "requires rollover timestamps even when record validation is sampled out" do
        event = publisher.round_trip(build_upsert_event(:widget, __exclude_fields: [:created_at]))
        adapter = indexer.ingestion_adapters_by_format.fetch("proto")
        expect(adapter.validate_event(event, skip_record_validation: true).failure).to have_attributes(message: include("created_at", "rollover index"))
      end

      it "builds no derived operations when the record omits its derived IDs" do
        event = publisher.round_trip(build_upsert_event(:widget, __exclude_fields: [:cost, :cost_currency_introduced_on]))
        result = indexer.operation_factory.build(event)
        expect(result.failed_event_error).to be_nil
        expect(result.operations.map { |op| op.update_target.type }).to eq(["Widget"])
      end

      %i[proto2 proto3].each do |syntax|
        context "with #{syntax}" do
          let(:schema_artifacts) do
            generate_schema_artifacts(extension_modules: [SchemaDefinition::APIExtension]) do |schema|
              schema.proto_schema_artifacts package_name: "elasticgraph", syntax: syntax
              schema.enum_type("State") { |type| type.values "ACTIVE", "onHold" }
              schema.object_type("Box") { |type|
                type.field "id", "ID!"
                type.field "width", "Int", name_in_index: "private_width"
                type.field "visits", "JsonSafeLong"
              }
              schema.object_type("Sphere") { |type|
                type.field "id", "ID!"
                type.field "radius", "Float"
              }
              schema.union_type("Shape") { |type|
                type.subtypes "Box", "Sphere"
                type.index "shapes"
              }
              schema.object_type("Attachment") { |type| type.field "label", "String" }
              schema.object_type "Product" do |type|
                type.field "id", "ID!"
                type.field "name", "String!", name_in_index: "private_name"
                type.field "active", "Boolean"
                type.field "quantity", "Int"
                type.field "large", "LongString"
                type.field "visits", "JsonSafeLong"
                type.field "visit_matrix", "[[JsonSafeLong]]"
                type.field "ratio", "Float"
                type.field "released", "Date"
                type.field "at", "DateTime"
                type.field "local_time", "LocalTime"
                type.field "zone", "TimeZone"
                type.field "state", "State"
                type.field "states", "[State]"
                type.field "shape", "Shape"
                type.field "grid", "[[[Int]]]"
                type.field "payload", "Untyped"
                type.field "attachment", "Attachment"
                type.index "products"
              end
            end
          end
          let(:adapter) { IngestionAdapter.new(schema_artifacts: schema_artifacts) }

          def event_for(record = {})
            publisher.round_trip(Indexer::Event.new(
              op: "upsert", type: "Product", id: "p1", version: 1,
              record: record, schema_version: nil, ingestion_format: "proto"
            ))
          end

          def prepare(result)
            result.record_preparer.prepare_for_index(result.event.type, result.event.record, nil)
          end

          it "preserves presence, nested lists and abstract types while preparing private field names" do
            event = event_for({
              "name" => "", "active" => false, "quantity" => 0, "large" => (2**63 - 1).to_s,
              "at" => "2024-02-29T12:34:56.123Z", "state" => "onHold", "states" => ["ACTIVE", "onHold"],
              "shape" => {"__typename" => "Box", "width" => 0}, "grid" => [[[0, 2], []], []],
              "payload" => {"nested" => [false, nil, 7]}
            })
            result = adapter.validate_event(event)
            expect(result.failure).to be_nil
            prepared = prepare(result)
            expect(prepared).to include(
              "id" => "p1", "private_name" => "", "active" => false, "quantity" => 0,
              "large" => 2**63 - 1, "at" => "2024-02-29T12:34:56.123Z", "state" => "onHold",
              "states" => ["ACTIVE", "onHold"], "shape" => {"private_width" => 0},
              "grid" => [[[0, 2], []], []], "payload" => "{\"nested\":[false,null,7]}"
            ).and exclude("name", "released")
            expect(event.record.id).to eq("")
          end

          it "preserves exact 64-bit values and the event version" do
            event = event_for("large" => (-2**63).to_s)
            expect(prepare(adapter.validate_event(event))).to include("large" => -2**63)
            event = publisher.round_trip(event.with(record: {"large" => (2**63 - 1).to_s}, version: 2**61 + 1))
            expect(event.version).to eq(2**61 + 1)
            expect(prepare(adapter.validate_event(event))).to include("large" => 2**63 - 1)
            [-(2**53 - 1), 2**53 - 1].each do |boundary|
              result = adapter.validate_event(event_for("visits" => boundary), skip_record_validation: true)
              expect(result.failure).to be_nil
              expect(prepare(result)).to include("visits" => boundary)
            end
          end

          it "accepts an absent non-null field without inventing a publisher schema version" do
            result = adapter.validate_event(event_for)
            expect(result.failure).to be_nil
            expect(prepare(result)).to exclude("private_name")
            expect(result.event.schema_version).to be_nil
          end

          it "maps unspecified enums and empty abstract wrappers to null" do
            event = event_for
            event.record.state = 0
            shape_class = event.record.class.descriptor.lookup("shape").subtype.msgclass
            event.record.shape = shape_class.new
            result = adapter.validate_event(event)
            expect(result.failure).to be_nil
            expect(prepare(result)).to include("state" => nil, "shape" => nil)
          end

          it "rejects unknown enum values even when record validation is sampled out" do
            event = event_for
            event.record.state = 1729
            expect(adapter.validate_event(event, skip_record_validation: true).failure).to have_attributes(message: include("record.state has an unknown enum value"))

            event = event_for
            event.record.states << 1729
            expect(adapter.validate_event(event, skip_record_validation: true).failure).to have_attributes(message: include("record.states[0] has an unknown enum value"))
          end

          it "rejects malformed Untyped values" do
            event = event_for
            event.record.payload = "private invalid json"
            expect(adapter.validate_event(event).failure).to have_attributes(message: include("record.payload is not a valid Untyped"))
          end

          it "validates scalar ranges and formats, including nested values" do
            {
              "visits" => [2**53, "record.visits"],
              "visit_matrix" => [[[1], [2**53]], "record.visit_matrix[1][0]"],
              "shape" => [{"__typename" => "Box", "visits" => 2**53}, "record.shape.visits"],
              "released" => ["2023-02-29", "record.released"],
              "local_time" => ["25:00:00", "record.local_time"],
              "zone" => ["Invalid/Zone", "record.zone"]
            }.each do |field, (value, expected_path)|
              result = adapter.validate_event(event_for(field => value))
              expect(result.failure).to have_attributes(message: include(expected_path))
            end

            event = event_for
            event.record.ratio = Float::INFINITY
            expect(adapter.validate_event(event).failure).to have_attributes(message: include("record.ratio"))

            timestamp_class = event_for.record.class.descriptor.lookup("at").subtype.msgclass
            [-62_135_596_801, 253_402_300_800].each do |bad_seconds|
              event = event_for
              event.record.at = timestamp_class.new(seconds: bad_seconds, nanos: 0)
              expect(adapter.validate_event(event).failure).to have_attributes(message: include("record.at"))
            end

            [-1, 1_000_000_000].each do |bad_nanos|
              event = event_for
              event.record.at = timestamp_class.new(seconds: 0, nanos: bad_nanos)
              expect(adapter.validate_event(event).failure).to have_attributes(message: include("record.at"))
            end

            result = adapter.validate_event(event_for(
              "released" => "2024-02-29",
              "at" => "2024-02-29T12:34:56.123Z",
              "local_time" => "12:34:56",
              "zone" => "America/Chicago",
              "ratio" => 0.5,
              "visit_matrix" => [[1, 2], []],
              "shape" => {"__typename" => "Box", "visits" => 42},
              "attachment" => {"label" => "ok"}
            ))
            expect(result.failure).to be_nil
          end

          it "honors sampling while always checking numeric ranges" do
            event = event_for("released" => "invalid", "active" => false)
            result = adapter.validate_event(event, skip_record_validation: true)
            expect(result.failure).to be_nil
            expect(prepare(result)).to include("active" => false)
            event = event_for("visits" => 2**53)
            expect(adapter.validate_event(event, skip_record_validation: true).failure).to have_attributes(message: include("visits"))
          end

          it "rejects a non-protobuf record or a protobuf record of the wrong type" do
            event = event_for
            expect(adapter.validate_event(event.with(record: {})).failure).to have_attributes(
              message: include("Expected a protobuf message of type elasticgraph.Product")
            )
            descriptor = event.record.class.descriptor.lookup("shape").subtype
            result = adapter.validate_event(event.with(record: descriptor.msgclass.new))
            expect(result.failure).to have_attributes(message: include("Expected a protobuf message of type elasticgraph.Product"))
          end

          it "resolves an abstract root to its concrete type and rejects an empty root" do
            event = Indexer::Event.new(op: "upsert", type: "Shape", id: "b1", version: 1,
              record: {"__typename" => "Box", "width" => 2}, schema_version: nil, ingestion_format: "proto")
            event = publisher.round_trip(event)
            result = adapter.validate_event(event)
            expect(result.failure).to be_nil
            expect(result.event.type).to eq("Box")
            expect(prepare(result)).to include("id" => "b1", "private_width" => 2)
            empty = event.with(record: event.record.class.new)
            expect(adapter.validate_event(empty).failure).to have_attributes(message: include("select a concrete subtype"))
          end

          it "rejects a known embedded type that has no indexing target" do
            event = event_for("attachment" => {"label" => "sample"})
            expect(adapter.validate_event(event.with(type: "Attachment", record: event.record.attachment)).failure).to have_attributes(message: include("not ingestible"))
          end
        end
      end

      it "requires protobuf runtime metadata" do
        artifacts = generate_schema_artifacts do |schema|
          schema.object_type("Item") { |type|
            type.field "id", "ID"
            type.index "items"
          }
        end
        expect { IngestionAdapter.new(schema_artifacts: artifacts) }.to raise_error(Errors::ConfigError, /Protobuf runtime metadata is missing/)
      end

      context "with an abstract parent of a rollover field" do
        let(:schema_artifacts) do
          generate_schema_artifacts(extension_modules: [SchemaDefinition::APIExtension]) do |schema|
            schema.interface_type("Occurrence") { |type| type.field "at", "DateTime", name_in_index: "timestamp" }
            schema.object_type "KnownOccurrence" do |type|
              type.implements "Occurrence"
              type.field "at", "DateTime", name_in_index: "timestamp"
            end
            schema.object_type "Item" do |type|
              type.field "id", "ID!"
              type.field "stamp", "Occurrence", name_in_index: "private_stamp"
              type.index("items") { |index| index.rollover :yearly, "stamp.at" }
            end
          end
        end

        it "reports the public path whether the abstract parent or its timestamp is absent" do
          adapter = IngestionAdapter.new(schema_artifacts: schema_artifacts)
          [nil, {"__typename" => "KnownOccurrence"}].each do |stamp|
            event = Indexer::Event.new(op: "upsert", type: "Item", id: "i1", version: 1,
              record: {"stamp" => stamp}, schema_version: nil, ingestion_format: "proto")
            result = adapter.validate_event(publisher.round_trip(event), skip_record_validation: true)
            expect(result.failure).to have_attributes(message: include("record.stamp.at", "rollover index"))
          end
        end
      end
    end
  end
end
