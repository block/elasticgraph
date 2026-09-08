# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/proto_ingestion/ingestion_adapter"
require "elastic_graph/proto_ingestion/indexing_event_decoder"
require "elastic_graph/spec_support/compiled_proto_support"

module ElasticGraph
  module ProtoIngestion
    RSpec.describe IngestionAdapter, :builds_indexer do
      include CompiledProtoSupport

      let(:results) do
        define_proto_schema_results do |s|
          s.on_built_in_types { |type| type.protobuf type: "string" if type.name == "DateTime" }
          s.enum_type("Status") { |t| t.values "ACTIVE", "RETIRED" }
          s.object_type("Box") { |t| t.field "size", "Int", name_in_index: "private_size" }
          s.object_type("Sphere") { |t| t.field "radius", "Float" }
          s.union_type("Shape") { |t| t.subtypes "Box", "Sphere" }
          s.object_type "Product" do |t|
            t.field "id", "ID!"
            t.field "displayName", "String!", name_in_index: "private_name"
            t.field "flag", "Boolean"
            t.field "quantity", "Int"
            t.field "safe", "JsonSafeLong"
            t.field "long", "LongString"
            t.field "ratio", "Float"
            t.field "date", "Date"
            t.field "timestamp", "DateTime"
            t.field "time", "LocalTime"
            t.field "zone", "TimeZone"
            t.field "payload", "Untyped"
            t.field "status", "Status"
            t.field "shape", "Shape"
            t.field "detail", "Box"
            t.field "tags", "[String!]!"
            t.field "cube", "[[[Int!]!]!]!"
            t.index "products"
          end
        end
      end
      let(:adapter) { IngestionAdapter.new(schema_artifacts: results, logger: Logger.new(StringIO.new)) }
      let(:event) { {"op" => "upsert", "type" => "Product", "id" => "p1", "version" => 1, "ingestion_format" => "proto", "record" => message} }
      let(:message) { @pool.lookup("elasticgraph.Product").msgclass.new(displayName: "name") }

      around do |example|
        with_compiled_proto(results) do |pool, path|
          @pool = pool
          @descriptor_path = path
          example.run
        end
      end

      it "preserves explicit false/zero, nulls and public names, reconstructs unions, and prepares private fields" do
        message.flag = false
        message.quantity = 0
        message.shape = @pool.lookup("elasticgraph.Shape").msgclass.new(box: {size: 2})
        message.payload = '{"integer":3,"float":3.0}'
        message.cube << @pool.lookup("elasticgraph.Product_cube_List1").msgclass.new(values: [{values: [1, 2]}, {values: []}])
        result = adapter.validate_event(event.merge("schema_version" => 99, "json_schema_version" => 2))
        expect(result.failure).to be_nil
        record = result.event.fetch("record")
        expect(record).to include("flag" => false, "quantity" => 0, "status" => nil, "date" => nil, "tags" => [],
          "shape" => {"__typename" => "Box", "size" => 2}, "cube" => [[[1, 2], []]], "payload" => {"integer" => 3, "float" => 3.0})
        expect(result.event).not_to include("schema_version", "json_schema_version")
        expect(result.record_preparer.prepare_for_index("Product", record, {"shape" => {"properties" => {"__typename" => {"type" => "keyword"}}}}))
          .to include("private_name" => "name", "shape" => {"__typename" => "Box", "private_size" => 2}, "payload" => '{"float":3.0,"integer":3}')
        expect(event.fetch("record")).to be(message)
      end

      it "maps an explicit unspecified enum and an empty oneof wrapper to null" do
        message.status = :STATUS_UNSPECIFIED
        message.shape = @pool.lookup("elasticgraph.Shape").msgclass.new
        expect(adapter.validate_event(event).event.fetch("record")).to include("status" => nil, "shape" => nil)
      end

      it "normalizes through both adapters regardless of their registration order" do
        require "elastic_graph/json_ingestion/ingestion_adapter"
        json = JSONIngestion::IngestionAdapter.new(schema_artifacts: stock_schema_artifacts, logger: Logger.new(StringIO.new))
        expect(json.handles_event?(event)).to be(false)
        expect(adapter.handles_event?(event)).to be(true)
        expect(adapter.handles_event?(event.except("ingestion_format"))).to be(false)
        [[json, adapter], [adapter, json]].each do |adapters|
          selected = adapters.find { |candidate| candidate.handles_event?(event) }
          expect(selected.validate_event(event).failure).to be_nil
        end
      end

      it "rejects a message of the wrong type and rejects missing required values" do
        expect(adapter.validate_event(event.merge("record" => @pool.lookup("elasticgraph.Box").msgclass.new)).failure.message).to include("Expected a protobuf message")
        message.clear_displayName
        expect(adapter.validate_event(event).failure.message).to include("record.displayName must not be null")
      end

      it "rejects malformed encoded Untyped values without exposing their contents" do
        message.payload = "private invalid JSON"
        result = adapter.validate_event(event)
        expect(result.failure.message).to eq("Invalid encoded scalar value.")
      end

      it "validates envelopes even when record validation is disabled" do
        changes = [
          {"op" => "delete"}, {"type" => "Box"}, {"id" => ""}, {"id" => 5},
          {"version" => 0}, {"version" => "1"}, {"version" => 2**63}, {"record" => nil},
          {"latency_timestamps" => []}, {"latency_timestamps" => {"published" => "2024-02-31T00:00:00Z"}}
        ]
        changes.each do |change|
          expect(adapter.validate_event(event.merge(change), skip_record_validation: true).failure).not_to be_nil
        end
        expect(adapter.validate_event(event.merge("latency_timestamps" => {"published" => "2024-02-29T23:59:59.123Z"})).failure).to be_nil
      end

      it "honors record-validation sampling while still performing record conversion" do
        message.date = "2024-02-30"
        expect(adapter.validate_event(event).failure.message).to include("record.date")
        result = adapter.validate_event(event, skip_record_validation: true)
        expect(result.failure).to be_nil
        expect(result.event.fetch("record").fetch("date")).to eq("2024-02-30")
      end

      it "validates canonical records when the operation factory retries validation after a skipped-validation error" do
        record = adapter.validate_event(event).event.fetch("record")
        invalid_values = {"displayName" => nil, "detail" => [], "tags" => [nil], "shape" => {"__typename" => "Unknown"},
                          "date" => "2024-02-30", "timestamp" => "2024-01-01T24:00:00Z", "time" => "99:00:00", "zone" => "Not/AZone",
                          "safe" => 2**53, "long" => 2**63, "ratio" => Float::INFINITY, "flag" => "false", "quantity" => 2**31, "status" => 99}
        invalid_values.each do |name, value|
          expect(adapter.validate_event(event.merge("record" => record.merge(name => value))).failure.message).to include("record.#{name}")
        end
        expect(adapter.validate_event(event.merge("record" => record.merge("tags" => "string"))).failure.message).to include("must be a list")
        expect(adapter.validate_event(event.merge("record" => record.merge("shape" => {"__typename" => "Box", "size" => "wrong"}))).failure.message).to include("record.shape.size")
        expect(adapter.validate_event(event.merge("record" => record.merge("shape" => nil))).failure).to be_nil
      end

      it "accepts valid built-in scalar values" do
        message.safe = 2**53 - 1
        message.long = -(2**63)
        message.ratio = 1.25
        message.date = "2024-02-29"
        message.timestamp = "2024-02-29T23:59:59.123+02:00"
        message.time = "12:34:56.789"
        message.zone = "America/Chicago"
        message.status = :STATUS_RETIRED
        expect(adapter.validate_event(event).failure).to be_nil
      end

      it "requires protobuf runtime metadata and validates decoder settings at boot" do
        expect { RuntimeSchema.new(stock_schema_artifacts) }.to raise_error(Errors::ConfigError, /runtime metadata is missing/)
        expect { decoder("format" => "unknown") }.to raise_error(Errors::ConfigError, /format/)
        expect { decoder("encoding" => "unknown") }.to raise_error(Errors::ConfigError, /encoding/)
      end

      it "rejects corrupt payloads and unknown raw types instead of guessing a format" do
        expect { decoder("encoding" => "base64").decode("not-base64") }.to raise_error(ArgumentError)
        expect { decoder.decode("\xFF".b) }.to raise_error(Google::Protobuf::ParseError)
        expect { decoder("format" => "raw").decode_with_metadata("", metadata: {"eg_type" => "Unknown"}) }.to raise_error(Errors::ConfigError, /No protobuf message/)
      end

      it "loads descriptor sets containing messages without a package" do
        descriptors = Google::Protobuf::FileDescriptorSet.decode(File.binread(@descriptor_path))
        descriptors.file << Google::Protobuf::FileDescriptorProto.new(
          name: "unpackaged.proto", syntax: "proto3", message_type: [Google::Protobuf::DescriptorProto.new(name: "Unpackaged")]
        )
        File.binwrite(@descriptor_path, Google::Protobuf::FileDescriptorSet.encode(descriptors))
        events = decoder("format" => "raw").decode_with_metadata(
          message.class.encode(message), metadata: {"eg_type" => "Product", "eg_op" => "upsert", "eg_id" => "p1", "eg_version" => "1"}
        )
        expect(adapter.validate_event(events.fetch(0)).failure).to be_nil
      end

      it "uses configured transport attribute names without requiring a schema version" do
        events = decoder("format" => "raw", "metadata_fields" => {"type" => "record_type"}).decode_with_metadata(
          message.class.encode(message), metadata: {"record_type" => "Product", "eg_op" => "upsert", "eg_id" => "p1", "eg_version" => "1"}
        )
        expect(adapter.validate_event(events.fetch(0)).failure).to be_nil
      end

      it "reports envelopes with no known oneof alternative as invalid events" do
        envelope = @pool.lookup("elasticgraph.ElasticGraphEventEnvelope").msgclass.new(op: "upsert", id: "unknown", version: 1)
        batch = @pool.lookup("elasticgraph.ElasticGraphEventBatch").msgclass
        events = decoder.decode(batch.encode(batch.new(events: [envelope])))
        expect(adapter.validate_event(events.fetch(0)).failure.message).to include("type must identify")
      end

      def decoder(config = {})
        IndexingEventDecoder.new(config: {"descriptor_set_file" => @descriptor_path}.merge(config), schema_artifacts: results, logger: Logger.new(StringIO.new))
      end
    end
  end
end
