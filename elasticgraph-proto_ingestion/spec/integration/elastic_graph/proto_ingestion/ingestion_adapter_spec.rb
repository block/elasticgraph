# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/indexer/event"
require "elastic_graph/proto_ingestion/indexer_extension"
require "elastic_graph/spec_support/proto_publisher"

module ElasticGraph
  module ProtoIngestion
    RSpec.describe IngestionAdapter, :builds_indexer, :factories do
      let(:indexer) { build_indexer(schema_artifacts: @schema_artifacts) }

      context "with the stock schema" do
        before(:context) do
          @schema_artifacts = stock_schema_artifacts
          @publisher = SpecSupport::ProtoPublisher.new(@schema_artifacts)
        end

        it "requires rollover timestamps even when record validation is sampled out" do
          event = @publisher.round_trip(build_upsert_event(:widget, __exclude_fields: [:created_at]))

          expect(sampled_out_failure_for(event)).to include("record.created_at", "rollover index")
        end
      end

      context "with a schema covering each kind of protobuf field" do
        # Defining the schema dominates each example's run time, and examples only read it, so we define it once.
        before(:context) do
          @schema_artifacts = generate_schema_artifacts(extension_modules: [SchemaDefinition::APIExtension]) do |schema|
            schema.proto_schema_artifacts package_name: "elasticgraph"
            schema.enum_type("State") { |type| type.values "ACTIVE", "onHold" }
            schema.scalar_type("Duration") do |type|
              type.mapping type: "keyword"
              type.protobuf type: "google.protobuf.Duration", import: "google/protobuf/duration.proto"
            end

            schema.object_type("Box") do |type|
              type.field "id", "ID!"
              type.field "width", "Int", name_in_index: "private_width"
              type.field "visits", "JsonSafeLong"
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
              type.field "name", "String!", name_in_index: "private_name"
              type.field "visits", "JsonSafeLong"
              type.field "visit_matrix", "[[JsonSafeLong]]"
              type.field "ratio", "Float"
              type.field "released", "Date"
              type.field "at", "DateTime"
              type.field "duration", "Duration"
              type.field "local_time", "LocalTime"
              type.field "zone", "TimeZone"
              type.field "state", "State"
              type.field "states", "[State]"
              type.field "shape", "Shape"
              type.field "payload", "Untyped"
              type.field "attachment", "Attachment"
              type.index "products"
            end
          end
          @publisher = SpecSupport::ProtoPublisher.new(@schema_artifacts)
        end

        it "copies the envelope `id` into the prepared record without mutating the published record" do
          event = publish

          result = indexer.operation_factory.build(event)

          expect(result.failed_event_error).to be_nil
          expect(result.operations.map(&:prepared_record)).to all include("id" => "p1")
          expect(event.record.id).to eq("")
        end

        it "accepts a record that omits a non-null field, since protobuf events carry no publisher schema version" do
          expect(failure_for(publish)).to be_nil
        end

        it "accepts the zero (unspecified) enum value" do
          expect(failure_for(publish { |record| record.state = 0 })).to be_nil
        end

        it "accepts an abstract-typed field that has no concrete subtype set" do
          event = publish { |record| record.shape = record.class.descriptor.lookup("shape").subtype.msgclass.new }

          expect(failure_for(event)).to be_nil
        end

        it "accepts valid values for each validated scalar" do
          event = publish({
            "visits" => 2**53 - 1,
            "visit_matrix" => [[-(2**53 - 1), 2], []],
            "ratio" => 0.5,
            "released" => "2024-02-29",
            "at" => "2024-02-29T12:34:56.123Z",
            "duration" => "30.5s",
            "local_time" => "12:34:56",
            "zone" => "America/Chicago",
            "shape" => {"__typename" => "Box", "visits" => 42},
            "payload" => {"nested" => [false, nil, 7]},
            "attachment" => {"label" => "ok"}
          })

          expect(failure_for(event)).to be_nil
        end

        {
          "a `JsonSafeLong` above its range" => [{"visits" => 2**53}, "record.visits"],
          "a `JsonSafeLong` below its range" => [{"visits" => -(2**53)}, "record.visits"],
          "a `JsonSafeLong` in a nested list" => [{"visit_matrix" => [[1], [2**53]]}, "record.visit_matrix[1][0]"],
          "a `JsonSafeLong` in an abstract-typed field" => [{"shape" => {"__typename" => "Box", "visits" => 2**53}}, "record.shape.visits"],
          "an impossible `Date`" => [{"released" => "2023-02-29"}, "record.released"],
          "an invalid `LocalTime`" => [{"local_time" => "25:00:00"}, "record.local_time"],
          "an unknown `TimeZone`" => [{"zone" => "Invalid/Zone"}, "record.zone"],
          "an invalid `Untyped` value" => [->(record) { record.payload = "invalid json" }, "record.payload"],
          "an infinite `Float`" => [->(record) { record.ratio = Float::INFINITY }, "record.ratio"],
          "a NaN `Float`" => [->(record) { record.ratio = Float::NAN }, "record.ratio"],
          "a `DateTime` before year 1" => [->(record) { record.at = timestamp(seconds: -62_135_596_801) }, "record.at"],
          "a `DateTime` after year 9999" => [->(record) { record.at = timestamp(seconds: 253_402_300_800) }, "record.at"],
          "a `DateTime` with negative nanos" => [->(record) { record.at = timestamp(nanos: -1) }, "record.at"],
          "a `DateTime` with nanos of a full second" => [->(record) { record.at = timestamp(nanos: 1_000_000_000) }, "record.at"]
        }.each do |description, (record_or_mutation, path)|
          it "rejects #{description}" do
            event = record_or_mutation.is_a?(::Hash) ? publish(record_or_mutation) : publish { |record| instance_exec(record, &record_or_mutation) }

            expect(failure_for(event)).to include("Malformed Product record.", path)
          end
        end

        it "skips format checks when record validation is sampled out" do
          expect(sampled_out_failure_for(publish({"released" => "invalid"}))).to be_nil
        end

        it "checks `JsonSafeLong` ranges even when record validation is sampled out" do
          expect(sampled_out_failure_for(publish({"visits" => 2**53}))).to include("record.visits")
        end

        it "rejects an unknown singular enum value even when record validation is sampled out" do
          event = publish { |record| record.state = 1729 }

          expect(sampled_out_failure_for(event)).to include("record.state has an unknown enum value")
        end

        it "rejects an unknown repeated enum value even when record validation is sampled out" do
          event = publish { |record| record.states << 1729 }

          expect(sampled_out_failure_for(event)).to include("record.states[0] has an unknown enum value")
        end

        it "rejects a record that is not a protobuf message" do
          expect(failure_for(publish.with(record: {}))).to include("Expected a protobuf message of type elasticgraph.Product")
        end

        it "rejects a protobuf record of a different type than the event" do
          event = publish
          shape = event.record.class.descriptor.lookup("shape").subtype.msgclass.new

          expect(failure_for(event.with(record: shape))).to include("Expected a protobuf message of type elasticgraph.Product")
        end

        it "indexes an abstract-typed root record as its concrete subtype" do
          event = publish({"__typename" => "Box", "width" => 2}, type: "Shape")

          result = indexer.operation_factory.build(event)

          expect(result.failed_event_error).to be_nil
          expect(result.operations.map(&:prepared_record)).to contain_exactly(include("id" => "p1", "private_width" => 2, "__typename" => "Box"))
        end

        it "rejects an abstract-typed root record that has no concrete subtype set" do
          event = publish({"__typename" => "Box"}, type: "Shape")

          expect(failure_for(event.with(record: event.record.class.new))).to include("select a concrete subtype")
        end

        it "rejects an event for an embedded type that has no index" do
          event = publish({"attachment" => {"label" => "sample"}})

          expect(failure_for(event.with(type: "Attachment", record: event.record.attachment))).to include("not ingestible")
        end

        def timestamp(seconds: 0, nanos: 0)
          publish.record.class.descriptor.lookup("at").subtype.msgclass.new(seconds: seconds, nanos: nanos)
        end
      end

      context "with an abstract parent of a rollover field" do
        before(:context) do
          @schema_artifacts = generate_schema_artifacts(extension_modules: [SchemaDefinition::APIExtension]) do |schema|
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
          @publisher = SpecSupport::ProtoPublisher.new(@schema_artifacts)
        end

        it "reports the public path to the rollover timestamp when its abstract parent is absent" do
          expect(sampled_out_failure_for(publish({}, type: "Item"))).to include("record.stamp.at", "rollover index")
        end

        it "reports the public path to the rollover timestamp when it is absent from its abstract parent" do
          event = publish({"stamp" => {"__typename" => "KnownOccurrence"}}, type: "Item")

          expect(sampled_out_failure_for(event)).to include("record.stamp.at", "rollover index")
        end
      end

      context "when `DateTime` is overridden to `string`" do
        before(:context) do
          @schema_artifacts = generate_schema_artifacts(extension_modules: [SchemaDefinition::APIExtension]) do |schema|
            schema.on_built_in_types do |type|
              type.protobuf type: "string" if type.name == "DateTime"
            end

            schema.object_type "Item" do |type|
              type.field "id", "ID!"
              type.field "at", "DateTime"
              type.index "items"
            end
          end
          @publisher = SpecSupport::ProtoPublisher.new(@schema_artifacts)
        end

        ["2024-02-29T12:34:56Z", "2024-02-29T06:34:56.123456-06:00", "2016-12-31T23:59:60Z"].each do |value|
          it "accepts the `DateTime` string #{value.inspect}" do
            expect(failure_for(publish({"at" => value}, type: "Item"))).to be_nil
          end
        end

        [
          "not-a-timestamp", "2023-02-29T12:00:00Z", "2024-02-29T24:00:00Z", "2024-02-29T12:60:00Z",
          "2024-02-29T12:00:61Z", "2024-02-29T12:00:00+25:00", "2024-02-29T12:00:00+01:60"
        ].each do |value|
          it "rejects the `DateTime` string #{value.inspect}" do
            expect(failure_for(publish({"at" => value}, type: "Item"))).to include("record.at is not a valid DateTime")
          end
        end
      end

      context "with a repeated derived `id_source` targeting a rollover index" do
        before(:context) do
          @schema_artifacts = generate_schema_artifacts(extension_modules: [SchemaDefinition::APIExtension]) do |schema|
            schema.object_type "Tag" do |type|
              type.field "id", "ID!"
              type.field "created_at", "DateTime"
              type.field "item_name", "String" do |field|
                field.sourced_from "item", "name"
              end
              type.relates_to_one "item", "Item", via: "tag_ids", dir: :in do |relationship|
                relationship.equivalent_field "created_at"
              end
              type.index("tags") do |index|
                index.rollover :yearly, "created_at"
                index.has_had_multiple_sources!
              end
            end

            schema.object_type "Item" do |type|
              type.field "id", "ID!"
              type.field "name", "String"
              type.field "tag_ids", "[ID!]"
              type.field "created_at", "DateTime"
              type.relates_to_many "tags", "Tag", via: "tag_ids", dir: :out, singular: "tag"
              type.index "items"
            end
          end
          @publisher = SpecSupport::ProtoPublisher.new(@schema_artifacts)
        end

        it "does not require the rollover timestamp when the repeated `id_source` is empty" do
          expect(failure_for(publish({"tag_ids" => []}, type: "Item"))).to be_nil
        end

        it "requires the rollover timestamp when the repeated `id_source` has values" do
          expect(failure_for(publish({"tag_ids" => ["t1"]}, type: "Item"))).to include("record.created_at", "rollover index")
        end
      end

      # Publishes `record` through real protobuf encoding, yielding the decoded native message for adjustments
      # that the publisher cannot express (such as values outside a scalar's valid range).
      def publish(record = {}, type: "Product")
        event = @publisher.round_trip(Indexer::Event.new(
          op: "upsert", type: type, id: "p1", version: 1,
          record: record, schema_version: nil, ingestion_format: "proto"
        ))
        yield event.record if block_given?
        event
      end

      def failure_for(event)
        indexer.operation_factory.build(event).failed_event_error&.message
      end

      # `build_indexer` intentionally does not expose record validation sampling, so these examples ask the
      # adapter for a sampled-out validation directly.
      def sampled_out_failure_for(event)
        indexer.ingestion_adapters_by_format.fetch("proto").validate_event(event, skip_record_validation: true).failure&.message
      end
    end
  end
end
