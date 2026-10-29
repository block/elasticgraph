# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/indexer/event"
require "elastic_graph/proto_ingestion/record_converter"
require "elastic_graph/proto_ingestion/runtime_schema"
require "elastic_graph/spec_support/proto_publisher"

module ElasticGraph
  module ProtoIngestion
    RSpec.describe "Protobuf record conversion" do
      %i[proto2 proto3].each do |syntax|
        context "with #{syntax}" do
          let(:schema_artifacts) { define_conversion_schema }
          let(:publisher) { SpecSupport::ProtoPublisher.new(schema_artifacts) }
          let(:runtime_schema) { RuntimeSchema.new(schema_artifacts) }

          it "preserves presence and exact integers without modifying the native record" do
            native = native_record({
              "name" => "", "active" => false, "quantity" => 0,
              "large" => 2**63 - 1, "visits" => 2**53 - 1
            })
            runtime_schema.register(native.class.descriptor)
            converted = RecordConverter.new(runtime_schema).convert("Product", native)

            expect(converted).to include(
              "name" => "", "active" => false, "quantity" => 0,
              "large" => 2**63 - 1, "visits" => 2**53 - 1,
              "states" => [], "attachments" => [], "grid" => []
            ).and exclude("id", "at", "state")
            expect(native.class.descriptor.lookup("id").has?(native)).to be(false)
            expect(native.name).to eq("")
            expect(convert({"large" => -2**63})).to include("large" => -2**63)
          end

          it "converts nested objects, abstract types, and nested lists" do
            converted = convert({
              "shape" => {"__typename" => "Box", "width" => 0},
              "attachments" => [{"label" => "sample"}], "grid" => [[[0, 2], []], []]
            })
            expect(converted).to include(
              "shape" => {"__typename" => "Box", "width" => 0},
              "attachments" => [{"label" => "sample"}], "grid" => [[[0, 2], []], []]
            )
            expect(convert({"__typename" => "Sphere", "radius" => 0.5}, type: "Shape")).to eq(
              "__typename" => "Sphere", "radius" => 0.5
            )
          end

          it "restores standard and non-standard enum names and preserves unknown values for validation" do
            expect(convert({"state" => "onHold", "states" => ["ACTIVE", "onHold"], "kind" => "SPECIAL"})).to include(
              "state" => "onHold", "states" => ["ACTIVE", "onHold"], "kind" => "SPECIAL"
            )
            native = native_record({})
            native.state = 0
            runtime_schema.register(native.class.descriptor)
            converter = RecordConverter.new(runtime_schema)
            expect(converter.convert("Product", native)).to include("state" => nil)
            native.state = 1729
            expect(converter.convert("Product", native)).to include("state" => 1729)
          end

          it "maps an empty abstract wrapper to null" do
            native = native_record({"__typename" => "Box", "width" => 1}, type: "Shape")
            runtime_schema.register(native.class.descriptor)
            expect(RecordConverter.new(runtime_schema).convert("Shape", native.class.new)).to be_nil
          end

          it "decodes encoded scalars and retains their formats" do
            expect(convert({
              "at" => "2024-02-29T12:34:56.123Z", "released" => "2024-02-29",
              "payload" => {"nested" => [false, nil, 7]}
            })).to include(
              "at" => "2024-02-29T12:34:56.123Z", "released" => "2024-02-29",
              "payload" => {"nested" => [false, nil, 7]}
            )
            native = native_record({})
            native.payload = "invalid json"
            runtime_schema.register(native.class.descriptor)
            expect { RecordConverter.new(runtime_schema).convert("Product", native) }.to raise_error(JSON::ParserError)
          end

          it "provides private field names and scalar preparers to the shared record preparer" do
            converted = convert({"name" => "sample", "shape" => {"__typename" => "Box", "width" => 2}})
            prepared = runtime_schema.record_preparer.prepare_for_index("Product", converted, nil)
            expect(prepared).to include("private_name" => "sample", "shape" => {"private_width" => 2}).and exclude("name")
            expect(runtime_schema.types.fetch("Product").fetch("fields").fetch("grid").fetch("type")).to eq("[[[Int]]]")
          end

          it "rebuilds the preparer when another root type is registered" do
            convert({"name" => "sample"})
            initial = runtime_schema.record_preparer
            descriptor = native_record({}, type: "Other").class.descriptor
            expect(runtime_schema.register(descriptor)).to eq("Other")
            updated = runtime_schema.record_preparer
            expect(updated).not_to be(initial)
            expect(updated.prepare_for_index("Other", {"label" => "second"}, nil)).to eq("private_label" => "second")
            runtime_schema.register(descriptor)
            expect(runtime_schema.record_preparer).to be(updated)
          end

          it "uses canonical scalar metadata after a built-in type is renamed" do
            artifacts = define_conversion_schema(type_name_overrides: {"JsonSafeLong" => "SafeLong"})
            renamed_publisher = SpecSupport::ProtoPublisher.new(artifacts)
            schema = RuntimeSchema.new(artifacts)
            native = native_record({"visits" => 2**53 - 1}, via: renamed_publisher)
            schema.register(native.class.descriptor)
            expect(schema.types.fetch("SafeLong").fetch("scalar")).to eq("JsonSafeLong")
            expect(RecordConverter.new(schema).convert("Product", native)).to include("visits" => 2**53 - 1)
          end

          def native_record(record, type: "Product", via: publisher)
            via.round_trip(Indexer::Event.new(
              op: "upsert", type: type, id: "p1", version: 1,
              record: record, schema_version: nil, ingestion_format: "proto"
            )).record
          end

          def convert(record, type: "Product")
            native = native_record(record, type: type)
            runtime_schema.register(native.class.descriptor)
            RecordConverter.new(runtime_schema).convert(type, native)
          end

          define_method :define_conversion_schema do |**options|
            define_proto_schema_results(**options) do |schema|
              schema.proto_schema_artifacts package_name: "conversion", syntax: syntax
              schema.enum_type("State") { |type| type.values "ACTIVE", "onHold" }
              schema.enum_type("Kind") { |type| type.values "STANDARD", "SPECIAL" }
              schema.object_type("Box") do |type|
                type.field "id", "ID!"
                type.field "width", "Int", name_in_index: "private_width"
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
              schema.object_type("Other") do |type|
                type.field "id", "ID!"
                type.field "label", "String", name_in_index: "private_label"
                type.index "others"
              end
              schema.object_type "Product" do |type|
                type.field "id", "ID!"
                type.field "name", "String", name_in_index: "private_name"
                type.field "active", "Boolean"
                type.field "quantity", "Int"
                type.field "large", "LongString"
                type.field "visits", "JsonSafeLong"
                type.field "at", "DateTime"
                type.field "released", "Date"
                type.field "payload", "Untyped"
                type.field "state", "State"
                type.field "states", "[State]"
                type.field "kind", "Kind"
                type.field "shape", "Shape"
                type.field("attachments", "[Attachment]") { |field| field.mapping type: "object" }
                type.field "grid", "[[[Int]]]"
                type.index "products"
              end
            end
          end
        end
      end

      it "requires the protobuf extension metadata" do
        artifacts = generate_schema_artifacts do |schema|
          schema.object_type("Item") do |type|
            type.field "id", "ID!"
            type.index "items"
          end
        end
        expect { RuntimeSchema.new(artifacts) }.to raise_error(Errors::ConfigError, /Protobuf runtime metadata is missing/)
      end
    end
  end
end
