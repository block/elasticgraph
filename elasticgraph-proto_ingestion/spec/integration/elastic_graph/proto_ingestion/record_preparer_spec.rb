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
      # Repeated fields have no presence, so they are prepared even when a record leaves them empty.
      let(:empty_lists) { {"states" => [], "attachments" => [], "grid" => []} }

      %i[proto2 proto3].each do |syntax|
        context "with #{syntax}" do
          # Defining the schema dominates each example's run time, and examples only read it, so we define it once.
          before(:context) do
            @schema_artifacts = define_preparation_schema(syntax)
            @publisher = SpecSupport::ProtoPublisher.new(@schema_artifacts)
          end

          let(:preparer) { described_class.new(@schema_artifacts) }

          it "omits singular fields that the record leaves unset" do
            expect(prepare(native_record)).to eq(empty_lists)
          end

          it "keeps singular fields that the record explicitly sets to their default values" do
            native = native_record({"name" => "", "active" => false, "quantity" => 0})

            expect(prepare(native)).to eq(empty_lists.merge("private_name" => "", "active" => false, "quantity" => 0))
          end

          [["large", -2**63], ["large", 2**63 - 1], ["visits", -(2**53 - 1)], ["visits", 2**53 - 1]].each do |field, value|
            it "preserves the exact `#{field}` value #{value}" do
              expect(prepare(native_record({field => value}))).to eq(empty_lists.merge(field => value))
            end
          end

          it "prepares nested objects" do
            native = native_record({"attachments" => [{"label" => "sample"}]})

            expect(prepare(native)).to eq(empty_lists.merge("attachments" => [{"label" => "sample"}]))
          end

          it "prepares nested lists, including empty inner lists" do
            native = native_record({"grid" => [[[0, 2], []], []]})

            expect(prepare(native)).to eq(empty_lists.merge("grid" => [[[0, 2], []], []]))
          end

          it "prepares an abstract-typed field from the fields of its concrete subtype" do
            native = native_record({"shape" => {"__typename" => "Box", "width" => 0}})

            expect(prepare(native)).to eq(empty_lists.merge("shape" => {"private_width" => 0}))
          end

          it "returns `nil` for an abstract-typed record that has no concrete subtype set" do
            empty_shape = native_record({"__typename" => "Box"}, type: "Shape").class.new

            expect(prepare(empty_shape, type: "Shape")).to be_nil
          end

          it "returns `nil` for a `nil` record" do
            expect(prepare(nil)).to be_nil
          end

          it "includes `__typename` on a nested object when its mapping has a `keyword` `__typename`" do
            native = native_record({"shape" => {"__typename" => "Box", "width" => 2}})
            mapping = {"shape" => {"properties" => {"__typename" => {"type" => "keyword"}}}}

            expect(prepare(native, mapping: mapping)).to eq(empty_lists.merge("shape" => {"__typename" => "Box", "private_width" => 2}))
          end

          it "includes the concrete `__typename` on an abstract-typed root record when its mapping has a `keyword` `__typename`" do
            native = native_record({"__typename" => "RoundSphere", "radius" => 0.5}, type: "Shape")

            expect(prepare(native, type: "Shape", mapping: {"__typename" => {"type" => "keyword"}})).to eq(
              "__typename" => "RoundSphere", "radius" => 0.5
            )
          end

          it "omits `__typename` when its mapping is a `constant_keyword`, since the index supplies it" do
            expect(prepare(native_record, mapping: {"__typename" => {"type" => "constant_keyword"}})).to eq(empty_lists)
          end

          it "converts enum values to their GraphQL names" do
            native = native_record({"state" => "onHold", "states" => ["ACTIVE", "onHold"], "kind" => "SPECIAL"})

            expect(prepare(native)).to eq(empty_lists.merge("state" => "onHold", "states" => ["ACTIVE", "onHold"], "kind" => "SPECIAL"))
          end

          it "prepares the zero (unspecified) enum value as `nil`" do
            native = native_record do |record|
              record.state = 0
              record.states.push(0)
            end

            expect(prepare(native)).to eq(empty_lists.merge("state" => nil, "states" => [nil]))
          end

          it "preserves enum numbers that have no defined value" do
            native = native_record do |record|
              record.state = 1729
              record.states.push(1729)
            end

            expect(prepare(native)).to eq(empty_lists.merge("state" => 1729, "states" => [1729]))
          end

          it "formats `DateTime` values with millisecond precision" do
            native = native_record({"at" => "2024-02-29T12:34:56.123456789Z"})

            expect(prepare(native)).to eq(empty_lists.merge("at" => "2024-02-29T12:34:56.123Z"))
          end

          it "prepares other external message scalars using their scalar's indexing preparation" do
            native = native_record({"duration" => "30.5s"})

            expect(prepare(native)).to eq(empty_lists.merge("duration" => "30.500s"))
          end

          it "prepares `DateTime` values overridden to `string` using `DateTime` indexing preparation" do
            artifacts = define_proto_schema_results do |schema|
              schema.proto_schema_artifacts package_name: "preparation", syntax: syntax
              schema.on_built_in_types do |type|
                type.protobuf type: "string" if type.name == "DateTime"
              end

              schema.object_type "Event" do |type|
                type.field "id", "ID!"
                type.field "at", "DateTime"
                type.index "events"
              end
            end
            native = native_record({"at" => "2024-02-29T06:34:56.123456789-06:00"}, type: "Event", via: SpecSupport::ProtoPublisher.new(artifacts))

            expect(prepare(native, type: "Event", via: described_class.new(artifacts))).to eq("at" => "2024-02-29T12:34:56.123Z")
          end

          it "prepares `Untyped` values as canonical JSON" do
            native = native_record({"payload" => {"z" => [false, nil, 7], "a" => 1}})

            expect(prepare(native)).to eq(empty_lists.merge("payload" => '{"a":1,"z":[false,null,7]}'))
          end

          it "raises an error when an `Untyped` value is not valid JSON" do
            native = native_record { |record| record.payload = "invalid json" }

            expect { prepare(native) }.to raise_error(::JSON::ParserError)
          end

          it "prepares records of different root types with the same preparer" do
            expect(prepare(native_record({"name" => "first"}))).to eq(empty_lists.merge("private_name" => "first"))
            expect(prepare(native_record({"label" => "second"}, type: "Other"), type: "Other")).to eq("private_label" => "second")
          end

          it "applies the canonical scalar preparation to renamed built-in scalars" do
            artifacts = define_preparation_schema(syntax, type_name_overrides: {"Untyped" => "Payload", "LongString" => "BigInt", "DateTime" => "Moment"})
            native = native_record(
              {"payload" => {"answer" => 42}, "large" => 99, "at" => "2024-02-29T12:34:56.123456789Z"},
              via: SpecSupport::ProtoPublisher.new(artifacts)
            )

            expect(prepare(native, via: described_class.new(artifacts))).to eq(
              empty_lists.merge("payload" => '{"answer":42}', "large" => 99, "at" => "2024-02-29T12:34:56.123Z")
            )
          end
        end
      end

      it "finds the protobuf runtime metadata among other registered indexer extensions" do
        stub_const("OtherIndexerExtension", ::Module.new)
        artifacts = define_proto_schema_results do |schema|
          schema.proto_schema_artifacts package_name: "preparation"
          # `defined_at` just needs a valid require path, but needs to be outside ElasticGraph
          # to not mess with our code coverage measurement.
          schema.register_indexer_extension OtherIndexerExtension, defined_at: "time"

          schema.object_type("Item") do |type|
            type.field "id", "ID!"
            type.field "label", "String", name_in_index: "private_label"
            type.index "items"
          end
        end
        native = native_record({"label" => "sample"}, type: "Item", via: SpecSupport::ProtoPublisher.new(artifacts))

        expect(prepare(native, type: "Item", via: described_class.new(artifacts))).to eq("private_label" => "sample")
      end

      it "raises a clear error when the schema artifacts lack protobuf runtime metadata" do
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

      # Publishes `record` through real protobuf encoding and returns the decoded native message. The message
      # is frozen (deeply, by `google-protobuf`), so every example also verifies that preparation does not mutate it.
      def native_record(record = {}, type: "Product", via: @publisher)
        native = via.round_trip(Indexer::Event.new(
          op: "upsert", type: type, id: "p1", version: 1,
          record: record, schema_version: nil, ingestion_format: "proto"
        )).record

        yield native if block_given?
        native.freeze
      end

      def prepare(native, type: "Product", mapping: nil, via: preparer)
        via.prepare_for_index(type, native, mapping)
      end

      def define_preparation_schema(syntax, **options)
        define_proto_schema_results(**options) do |schema|
          schema.proto_schema_artifacts package_name: "preparation", syntax: syntax
          schema.enum_type("State") { |type| type.values "ACTIVE", "onHold" }
          schema.enum_type("Kind") { |type| type.values "STANDARD", "SPECIAL" }
          schema.scalar_type("Duration") do |type|
            type.mapping type: "keyword"
            type.protobuf type: "google.protobuf.Duration", import: "google/protobuf/duration.proto"
          end

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
            type.field "duration", "Duration"
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
end
