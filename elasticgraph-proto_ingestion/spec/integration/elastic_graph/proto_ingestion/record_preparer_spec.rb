# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/indexer/event"
require "elastic_graph/proto_ingestion/record_preparer"
require "elastic_graph/spec_support/proto_publisher"

module ElasticGraph
  module ProtoIngestion
    RSpec.describe RecordPreparer do
      %i[proto2 proto3].each do |syntax|
        context "with #{syntax}" do
          let(:schema_artifacts) { define_preparation_schema }
          let(:publisher) { SpecSupport::ProtoPublisher.new(schema_artifacts) }
          let(:preparer) { described_class.new(schema_artifacts) }

          it "preserves presence and exact integers without modifying or expanding the native record" do
            native = native_record({
              "name" => "", "active" => false, "quantity" => 0,
              "large" => 2**63 - 1, "visits" => 2**53 - 1
            })
            forbid_hash_conversion(native)
            native.freeze
            expect(::Google::Protobuf).not_to receive(:encode_json)

            expect(preparer.prepare_for_index("Product", native, nil)).to include(
              "private_name" => "", "active" => false, "quantity" => 0,
              "large" => 2**63 - 1, "visits" => 2**53 - 1,
              "states" => [], "attachments" => [], "grid" => []
            ).and exclude("id", "name", "at", "state")
            expect(native.has_id?).to be(false)
            expect(native.name).to eq("")
            expect(prepare({"large" => -2**63})).to include("large" => -2**63)
          end

          it "prepares nested objects, abstract types, and nested lists directly into index fields" do
            native = native_record({
              "shape" => {"__typename" => "Box", "width" => 0},
              "attachments" => [{"label" => "sample"}], "grid" => [[[0, 2], []], []]
            })
            forbid_hash_conversion(native.shape.box)
            native.freeze

            expect(preparer.prepare_for_index("Product", native, nil)).to include(
              "shape" => {"private_width" => 0},
              "attachments" => [{"label" => "sample"}], "grid" => [[[0, 2], []], []]
            )
            expect(native.shape.box.width).to eq(0)
            expect(native.attachments.first.label).to eq("sample")
            expect(native.grid.first.values.first.values.to_a).to eq([0, 2])
          end

          it "includes concrete type names only where the destination mapping requires them" do
            properties = {
              "__typename" => {"type" => "constant_keyword"},
              "shape" => {"properties" => {"__typename" => {"type" => "keyword"}}}
            }
            native = native_record({"shape" => {"__typename" => "Box", "width" => 2}})
            expect(preparer.prepare_for_index("Product", native, properties)).to include(
              "shape" => {"__typename" => "Box", "private_width" => 2}
            ).and exclude("__typename")

            native = native_record({"__typename" => "RoundSphere", "radius" => 0.5}, type: "Shape")
            expect(preparer.prepare_for_index("Shape!", native, {"__typename" => {"type" => "keyword"}})).to eq(
              "__typename" => "RoundSphere", "radius" => 0.5
            )
            expect(prepare({}, mapping: {"__typename" => {"type" => "keyword"}})).to include("__typename" => "Product")
          end

          it "restores all enum names, maps zero to null, and preserves unknown values" do
            expect(prepare({"state" => "onHold", "states" => ["ACTIVE", "onHold"], "kind" => "SPECIAL"})).to include(
              "state" => "onHold", "states" => ["ACTIVE", "onHold"], "kind" => "SPECIAL"
            )
            native = native_record({})
            native.state = 0
            native.states.push(0, 1, 1729)
            expect(preparer.prepare_for_index("Product", native, nil)).to include("state" => nil, "states" => [nil, "ACTIVE", 1729])
            native.state = 1729
            expect(preparer.prepare_for_index("Product", native, nil)).to include("state" => 1729)
          end

          it "maps empty abstract wrappers and null records to null" do
            native = native_record({"__typename" => "Box", "width" => 1}, type: "Shape")
            expect(preparer.prepare_for_index("Shape", native.class.new, nil)).to be_nil
            expect(preparer.prepare_for_index("Product", nil, nil)).to be_nil
          end

          it "decodes scalar leaves and applies the shared scalar preparation rules" do
            expect(prepare({
              "at" => "2024-02-29T12:34:56.123456789Z", "released" => "2024-02-29",
              "payload" => {"z" => [false, nil, 7], "a" => 1}
            })).to include(
              "at" => "2024-02-29T12:34:56.123Z", "released" => "2024-02-29",
              "payload" => '{"a":1,"z":[false,null,7]}'
            )
            native = native_record({})
            native.payload = "invalid json"
            expect { preparer.prepare_for_index("Product", native, nil) }.to raise_error(::JSON::ParserError)
          end

          it "prepares every root type and caches compiled message plans across records" do
            expect(prepare({"name" => "sample"})).to include("private_name" => "sample")
            expect(prepare({"label" => "second"}, type: "Other")).to include("private_label" => "second")

            again = native_record({"name" => "again"})
            expect(again.class).not_to receive(:descriptor)
            expect(preparer.prepare_for_index("Product", again, nil)).to include("private_name" => "again")
          end

          it "uses canonical scalar metadata after built-in types are renamed" do
            artifacts = define_preparation_schema(type_name_overrides: {"Untyped" => "Payload", "LongString" => "BigInt", "DateTime" => "Moment"})
            renamed_publisher = SpecSupport::ProtoPublisher.new(artifacts)
            native = native_record({"payload" => {"answer" => 42}, "large" => 99, "at" => "2024-02-29T12:34:56.123456789Z"}, via: renamed_publisher)

            expect(described_class.new(artifacts).prepare_for_index("Product", native, nil)).to include(
              "payload" => '{"answer":42}', "large" => 99, "at" => "2024-02-29T12:34:56.123Z"
            )
          end

          def native_record(record, type: "Product", via: publisher)
            via.round_trip(Indexer::Event.new(
              op: "upsert", type: type, id: "p1", version: 1,
              record: record, schema_version: nil, ingestion_format: "proto"
            )).record
          end

          def prepare(record, type: "Product", mapping: nil)
            preparer.prepare_for_index(type, native_record(record, type: type), mapping)
          end

          def forbid_hash_conversion(message)
            # Mocking a native message gives it a singleton class, which breaks descriptor lookup on JRuby.
            message.class.prepend(::Module.new do
              def to_h
                # simplecov:disable -- only fails when preparation expands a native record into a public hash.
                raise "Native records must not be expanded into public hashes."
                # simplecov:enable
              end
            end)
          end

          define_method :define_preparation_schema do |**options|
            define_proto_schema_results(**options) do |schema|
              schema.proto_schema_artifacts package_name: "preparation", syntax: syntax
              schema.enum_type("State") { |type| type.values "ACTIVE", "onHold" }
              schema.enum_type("Kind") { |type| type.values "STANDARD", "SPECIAL" }

              schema.object_type("Box") do |type|
                type.field "id", "ID!"
                type.field "width", "Int", name_in_index: "private_width"
              end

              schema.object_type("RoundSphere") do |type|
                type.field "id", "ID!"
                type.field "radius", "Float"
              end

              schema.union_type("Shape") do |type|
                type.subtypes "Box", "RoundSphere"
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
                type.field "states", "[State!]!"
                type.field "kind", "Kind"
                type.field "shape", "Shape"
                type.field("attachments", "[Attachment]") { |field| field.mapping type: "object" }
                type.field "grid", "[[[Int!]!]!]!"
                type.index "products"
              end
            end
          end
        end
      end

      it "requires the protobuf extension metadata" do
        artifacts = define_schema(schema_element_name_form: :snake_case) do |schema|
          schema.object_type("Item") do |type|
            type.field "id", "ID!"
            type.index "items"
          end
        end
        expect { described_class.new(artifacts) }.to raise_error(
          Errors::ConfigError,
          /Protobuf runtime metadata is missing\. Enable `ElasticGraph::ProtoIngestion::SchemaDefinition::APIExtension`/
        )
      end
    end
  end
end
