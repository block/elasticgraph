# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/indexer/event"
require "elastic_graph/schema_artifacts/from_disk"
require "elastic_graph/spec_support/proto_publisher"

module ElasticGraph
  RSpec.describe SpecSupport::ProtoPublisher do
    %i[proto2 proto3].each do |syntax|
      context "with #{syntax}" do
        let(:schema_artifacts) { define_publisher_schema }
        let(:publisher) { described_class.new(schema_artifacts) }
        let(:event) do
          Indexer::Event.new(
            op: "upsert", type: "Product", id: "p1", version: 2**61 + 1,
            record: {}, schema_version: 1, ingestion_format: "json", message_id: "transport-id",
            latency_timestamps: {"published_at" => "2024-02-29T12:34:56.123Z"}
          )
        end

        it "encodes a real protobuf event batch and returns its native record" do
          original = event.with(record: {"name" => "published", "large" => 2**63 - 1})
          bytes = publisher.encode(original)
          decoded = run_protoc(schema_artifacts.proto_schema, "--decode=publisher.ElasticGraphEventBatch", bytes)
          expect(decoded).to include('name: "published"', "version: #{original.version}", "large: #{2**63 - 1}")

          result = publisher.round_trip(original)
          expect(result).to have_attributes(
            op: original.op, type: original.type, id: original.id, version: original.version,
            schema_version: nil, ingestion_format: "proto", message_id: original.message_id,
            latency_timestamps: original.latency_timestamps
          )
          expect(result.record).not_to be_a(Hash)
          expect(result.record.class.descriptor.name).to eq("publisher.Product")
          expect(result.record.name).to eq("published")
          expect(result.record.large).to eq(2**63 - 1)
          expect(original.record).to eq("name" => "published", "large" => 2**63 - 1)
        end

        it "preserves explicit defaults and omits absent, null, and unknown fields" do
          record = publisher.round_trip(event.with(record: {
            "name" => "", "active" => false, "quantity" => 0,
            "released" => nil, "unknown" => "ignored"
          })).record
          %w[name active quantity].each do |name|
            expect(record.class.descriptor.lookup(name).has?(record)).to be(true)
          end
          expect(record.name).to eq("")
          expect(record.active).to be(false)
          expect(record.quantity).to eq(0)
          expect(record.class.descriptor.lookup("released").has?(record)).to be(false)
          expect(record.class.descriptor.lookup("id").has?(record)).to be(false)
          expect(record.class.descriptor.lookup("unknown")).to be_nil
          expect(record.class.descriptor.lookup("private_name")).to be_nil
        end

        it "encodes enums, scalar overrides, nested objects, and nested lists" do
          record = publisher.round_trip(event.with(record: {
            "state" => "onHold", "states" => ["ACTIVE", "onHold"], "kind" => "SPECIAL",
            "large" => -2**63, "visits" => 2**53 - 1,
            "at" => "2024-02-29T12:34:56.123Z", "released" => "2024-02-29",
            "payload" => {"nested" => [false, nil, 7]},
            "shape" => {"__typename" => "Box", "width" => 0},
            "attachments" => [{"label" => "sample"}], "grid" => [[[0, 2], []], []]
          })).record
          expect(record.state).to eq(:STATE_ON_HOLD)
          expect(record.states.to_a).to eq([:STATE_ACTIVE, :STATE_ON_HOLD])
          expect(record.kind).to eq(:KIND_SPECIAL)
          expect(record.large).to eq(-2**63)
          expect(record.visits).to eq(2**53 - 1)
          expect(Google::Protobuf.encode_json(record.at)).to eq('"2024-02-29T12:34:56.123Z"')
          expect(record.released).to eq("2024-02-29")
          expect(JSON.parse(record.payload)).to eq("nested" => [false, nil, 7])
          expect(record.shape.box.width).to eq(0)
          expect(record.attachments.map(&:label)).to eq(["sample"])
          expect(record.grid.map { |row| row.values.map { |cell| cell.values.to_a } }).to eq([[[0, 2], []], []])
        end

        it "publishes abstract root records through their concrete alternative" do
          result = publisher.round_trip(event.with(type: "Shape", record: {"__typename" => "Sphere", "radius" => 0.5}))
          expect(result.type).to eq("Shape")
          expect(result.record.class.descriptor.name).to eq("publisher.Shape")
          expect(result.record.sphere.radius).to eq(0.5)
        end

        it "decodes an earlier publisher's bytes using the current schema" do
          current_schema = define_publisher_schema(schema_artifacts) do |type|
            type.field "new_field", "String"
          end
          current_publisher = described_class.new(current_schema)
          original = event.with(record: {"name" => "historical", "new_field" => "not in the old schema"})
          historical = current_publisher.round_trip(original, publisher: publisher).record
          current = current_publisher.round_trip(original).record

          expect(historical.name).to eq("historical")
          expect(historical.class.descriptor.lookup("new_field").has?(historical)).to be(false)
          expect(current.new_field).to eq("not in the old schema")
        end

        it "reports compiler errors" do
          allow(schema_artifacts).to receive(:proto_schema).and_return("invalid protobuf schema")
          expect { publisher }.to raise_error(RuntimeError, /schema.proto.*Expected/m)
        end

        define_method :define_publisher_schema do |prior_results = nil, &extra_fields|
          define_proto_schema_results(prior_results) do |schema|
            schema.proto_schema_artifacts package_name: "publisher", syntax: syntax
            schema.enum_type("State") { |type| type.values "ACTIVE", "onHold" }
            schema.enum_type("Kind") { |type| type.values "STANDARD", "SPECIAL" }
            schema.object_type("Box") do |type|
              type.field "id", "ID!"
              type.field "width", "Int"
            end
            schema.object_type("Sphere") do |type|
              type.field "id", "ID!"
              type.field "radius", "Float"
            end
            schema.union_type("Shape") do |type|
              type.subtypes "Box", "Sphere"
              type.index "shapes"
            end
            schema.object_type("Attachment") { |type| type.field "label", "String" }
            schema.object_type "Product" do |type|
              type.field "id", "ID!"
              type.field "name", "String", name_in_index: "private_name"
              type.field "active", "Boolean"
              type.field "quantity", "Int"
              type.field "large", "LongString"
              type.field "visits", "JsonSafeLong"
              type.field "released", "Date"
              type.field "at", "DateTime"
              type.field "state", "State"
              type.field "states", "[State]"
              type.field "kind", "Kind"
              type.field "payload", "Untyped"
              type.field "shape", "Shape"
              type.field("attachments", "[Attachment]") { |field| field.mapping type: "object" }
              type.field "grid", "[[[Int]]]"
              type.index "products"
              extra_fields&.call(type)
            end
          end
        end
      end
    end

    it "loads a schema from disk-backed artifacts" do
      artifacts = SchemaArtifacts::FromDisk.new(File.join(CommonSpecHelpers::REPO_ROOT, "config/schema/artifacts"))
      publisher = described_class.new(artifacts)
      event = Indexer::Event.new(
        op: "upsert", type: "Component", id: "c1", version: 1,
        record: {"name" => "from disk"}, schema_version: nil, ingestion_format: "proto"
      )

      expect(publisher.round_trip(event).record.name).to eq("from disk")
    end
  end
end
