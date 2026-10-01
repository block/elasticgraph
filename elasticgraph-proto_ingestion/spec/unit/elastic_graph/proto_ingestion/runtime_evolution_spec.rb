# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/proto_ingestion/indexing_event_decoder"
require "elastic_graph/proto_ingestion/ingestion_adapter"
require "elastic_graph/spec_support/compiled_proto_support"

module ElasticGraph
  module ProtoIngestion
    RSpec.describe "Protobuf runtime schema evolution", :builds_indexer do
      include CompiledProtoSupport

      it "maps stable message, field, union and enum names to current public names after rename declarations are removed" do
        original = renamed_schema
        current = renamed_schema(original, renamed: true)
        current = renamed_schema(current, renamed: true, declarations: false)
        with_compiled_proto(original) do |publisher, _|
          record = publisher.lookup("elasticgraph.Product").msgclass.new(
            full_name: "name", detail: {size: 2}, shape: {box: {size: 3}}, status: :STATUS_ACTIVE
          )
          bytes = envelope_bytes(publisher, product: record)
          with_compiled_proto(current) do |_, path|
            decoder = build_decoder(current, path)
            decoded = decoder.decode(bytes).fetch(0)
            expect(decoded.fetch("type")).to eq("Item")
            adapter = IngestionAdapter.new(schema_artifacts: current)
            events, failures = adapter.events_from([decoded])
            expect(failures).to be_empty
            result = adapter.validate_event(events.fetch(0))
            expect(result.failure).to be_nil
            expect(result.event.record).to include(
              "name" => "name", "detail" => {"length" => 2},
              "shape" => {"__typename" => "Cube", "length" => 3}, "status" => "ENABLED"
            )
            expect(result.record_preparer.prepare_for_index("Item", result.event.record, nil)).to include("private_name" => "name")
            %w[Product Item].each do |type|
              raw = build_decoder(current, path, "format" => "raw").decode_with_metadata(
                record.class.encode(record), metadata: {"eg_type" => type, "eg_op" => "upsert", "eg_id" => "p1", "eg_version" => "1"}
              )
              expect(raw.fetch(0).fetch("type")).to eq("Item")
            end
          end
        end
      end

      it "rejects historical values outside the current integer range even when validation is sampled out, including nested lists" do
        original = integer_schema
        current = integer_schema(original, narrowed: true)
        with_compiled_proto(original) do |publisher, _|
          record = publisher.lookup("elasticgraph.Product").msgclass.new(quantity: 2**31)
          record.cube << publisher.lookup("elasticgraph.Product.CubeList").msgclass.new(values: [2**31])
          with_compiled_proto(current) do |_, path|
            adapter = IngestionAdapter.new(schema_artifacts: current)
            ["quantity", "cube"].each do |field|
              message = record.dup
              message.clear_quantity if field == "cube"
              decoded = build_decoder(current, path).decode(envelope_bytes(publisher, product: message))
              events, failures = adapter.events_from(decoded)
              expect(failures).to be_empty
              result = adapter.validate_event(events.fetch(0), skip_record_validation: true)
              expect(result.failure.message).to include("record.#{field}", "valid Int")
            end
            record.quantity = INT_MAX
            record.cube.clear
            events, = adapter.events_from(build_decoder(current, path).decode(envelope_bytes(publisher, product: record)))
            result = adapter.validate_event(events.fetch(0), skip_record_validation: true)
            expect(result.failure).to be_nil
            expect(result.event.record.fetch("quantity")).to eq(INT_MAX)
          end
        end
      end

      %i[proto2 proto3].each do |syntax|
        it "drops only known retired #{syntax} enum values according to the syntax's presence semantics" do
          original = enum_schema(syntax: syntax)
          current = enum_schema(original, syntax: syntax, retired: true)
          with_compiled_proto(original) do |publisher, _|
            record = publisher.lookup("elasticgraph.Product").msgclass.new(status: :STATUS_RETIRED, statuses: [:STATUS_ACTIVE, :STATUS_RETIRED])
            with_compiled_proto(current) do |_, path|
              adapter = IngestionAdapter.new(schema_artifacts: current)
              events, = adapter.events_from(build_decoder(current, path).decode(envelope_bytes(publisher, product: record)))
              result = adapter.validate_event(events.fetch(0), skip_record_validation: true)
              expect(result.failure).to be_nil
              expect(result.event.record["status"]).to be_nil
              expect(result.event.record.fetch("statuses")).to eq(["ACTIVE", nil])
              [99, -1].each do |unknown|
                record.status = unknown
                events, = adapter.events_from(build_decoder(current, path).decode(envelope_bytes(publisher, product: record)))
                expect(adapter.validate_event(events.fetch(0), skip_record_validation: true).failure.message).to include("unknown enum value")
              end
            end
          end
        end
      end

      it "ignores only an unambiguous deleted record in envelopes and deleted raw types" do
        original = deletion_schema
        current = deletion_schema(original, deleted: true)
        with_compiled_proto(original) do |publisher, _|
          dead_record = publisher.lookup("elasticgraph.Removed").msgclass.new(name: "gone")
          dead_envelope = publisher.lookup("elasticgraph.ElasticGraphEventEnvelope").msgclass.new(op: "upsert", id: "r1", version: 1, removed: dead_record)
          dead_bytes = dead_envelope.class.encode(dead_envelope)
          live_record = publisher.lookup("elasticgraph.Product").msgclass.new(name: "live")
          live_envelope = publisher.lookup("elasticgraph.ElasticGraphEventEnvelope").msgclass.new(op: "upsert", id: "p1", version: 1, product: live_record)
          live_bytes = live_envelope.class.encode(live_envelope)
          unknown = length_delimited_field(99, "")
          with_compiled_proto(current) do |_, path|
            decoder = build_decoder(current, path)
            expect(decoder.decode(batch_bytes(dead_bytes))).to be_empty
            expect(build_decoder(current, path, "format" => "raw").decode_with_metadata("", metadata: {"eg_type" => "Removed"})).to be_empty
            expect(IngestionAdapter.new(schema_artifacts: current).events_from([{"type" => "Removed"}])).to eq([[], []])
            [dead_bytes + live_bytes, live_bytes + dead_bytes, dead_bytes + unknown,
              unknown + dead_bytes, dead_bytes + dead_bytes, live_bytes + live_bytes, unknown].each do |ambiguous|
              events = decoder.decode(batch_bytes(ambiguous))
              valid, failures = IngestionAdapter.new(schema_artifacts: current).events_from(events)
              expect(valid).to be_empty
              expect(failures.fetch(0).message).to include("exactly one supported record")
            end
            expect(decoder.decode(batch_bytes(dead_bytes, live_bytes)).map { |e| e.fetch("type") }).to eq(["Product"])
          end
        end
      end

      it "ignores historical envelopes after the final ingestible type is deleted" do
        original = define_proto_schema_results do |schema|
          schema.object_type("Product") do |t|
            t.field "id", "ID!"
            t.field "name", "String"
            t.index "products"
          end
        end
        current = define_proto_schema_results(original) { |schema| schema.deleted_type "Product" }
        with_compiled_proto(original) do |publisher, _|
          bytes = envelope_bytes(publisher, product: {name: "gone"})
          with_compiled_proto(current) do |_, path|
            expect(build_decoder(current, path).decode(bytes)).to be_empty
            expect(build_decoder(current, path, "format" => "raw").decode_with_metadata("", metadata: {"eg_type" => "Product"})).to be_empty
            decoded = build_decoder(current, path).decode(envelope_bytes(publisher))
            valid, failures = IngestionAdapter.new(schema_artifacts: current).events_from(decoded)
            expect(valid).to be_empty
            expect(failures.fetch(0).message).to include("type must identify")
          end
        end
      end

      it "does not ignore a retired envelope alternative belonging to a still-defined non-ingestible type" do
        original = deletion_schema
        current = define_proto_schema_results(original) do |schema|
          schema.object_type("Product") { |t|
            t.field "id", "ID!"
            t.field "name", "String"
            t.index "products"
          }
          schema.object_type("Removed") { |t|
            t.field "id", "ID!"
            t.field "name", "String"
          }
        end
        with_compiled_proto(original) do |publisher, _|
          bytes = envelope_bytes(publisher, removed: {name: "not deleted"})
          with_compiled_proto(current) do |_, path|
            events = build_decoder(current, path).decode(bytes)
            valid, failures = IngestionAdapter.new(schema_artifacts: current).events_from(events)
            expect(valid).to be_empty
            expect(failures.fetch(0).message).to include("supported record")
          end
        end
      end

      it "validates original wire tags and lengths instead of mistaking nested bytes for deleted records" do
        original = deletion_schema
        current = deletion_schema(original, deleted: true)
        with_compiled_proto(current) do |pool, path|
          decoder = build_decoder(current, path)
          reserved = current.runtime_metadata.indexer_extension_modules.last.extension_ref.fetch("config").fetch("reserved_envelope_fields").keys.first.to_i
          record = pool.lookup("elasticgraph.Product").msgclass.new(name: length_delimited_field(reserved, ""))
          expect(decoder.decode(envelope_bytes(pool, product: record)).size).to eq(1)
          ["\x00".b, "\x00\x00".b, "\xFF".b, "\x80".b * 10 + "\x00".b,
            "\x08".b + "\xFF".b * 9 + "\x02".b, "\x10".b + "\xFF".b * 9 + "\x02".b,
            "\x0A\x05x".b, "\x12\x05x".b,
            "\x09\x00".b, "\x0D\x00".b, "\x19\x00".b, "\x25\x00".b, "\x0B".b].each do |corrupt|
            expect { decoder.decode(corrupt) }.to raise_error(Google::Protobuf::ParseError)
          end
          # All protobuf primitive wire types can occur in fields unknown to the batch contract.
          expect(decoder.decode("\x10\x01\x19".b + "\x00".b * 8 + "\x25".b + "\x00".b * 4)).to be_empty
          expect { decoder.decode("\x08\x01".b) }.to raise_error(Google::Protobuf::ParseError, /length-delimited/)
          invalid_tag = varint((536_870_912 << 3) | 2) + "\x00".b
          expect { decoder.decode(invalid_tag) }.to raise_error(Google::Protobuf::ParseError, /field number/)
        end
      end

      it "requires a missing rollover timestamp using its current public path even when record validation is sampled out" do
        original = rollover_schema
        current = rollover_schema(original, renamed: true)
        with_compiled_proto(current) do |pool, path|
          adapter = IngestionAdapter.new(schema_artifacts: current)
          record = pool.lookup("elasticgraph.Product").msgclass.new
          events, = adapter.events_from(build_decoder(current, path).decode(envelope_bytes(pool, product: record)))
          expect(adapter.validate_event(events.fetch(0), skip_record_validation: true).failure.message).to include("record.created", "rollover index")
          record.created_at = "2024-02-29"
          events, = adapter.events_from(build_decoder(current, path).decode(envelope_bytes(pool, product: record)))
          expect(adapter.validate_event(events.fetch(0), skip_record_validation: true).failure).to be_nil
        end
      end

      it "requires a nested abstract rollover timestamp only when a derived target has IDs" do
        results = define_proto_schema_results do |schema|
          schema.object_type("Destination") do |type|
            type.field "id", "ID!"
            type.field "created", "Date"
            type.field "names", "[String!]!"
            type.index("destinations") { |index| index.rollover :yearly, "created" }
          end
          schema.object_type("Period") do |type|
            type.field "created", "Date", name_in_index: "private_created"
          end
          schema.union_type("Schedule") { |type| type.subtypes "Period" }
          schema.object_type("Product") do |type|
            type.field "id", "ID!"
            type.field "destination_id", "ID", name_in_index: "private_destination"
            type.field "name", "String"
            type.field "schedule", "Schedule", name_in_index: "private_schedule"
            type.index "products"
            type.derive_indexed_type_fields("Destination", from_id: "destination_id", rollover_with: "schedule.created") do |derive|
              derive.append_only_set "names", from: "name"
            end
          end
        end
        with_compiled_proto(results) do |pool, path|
          adapter = IngestionAdapter.new(schema_artifacts: results)
          [nil, ""].each do |id|
            attributes = id.nil? ? {} : {destination_id: id}
            decoded = build_decoder(results, path).decode(envelope_bytes(pool, product: attributes))
            events, = adapter.events_from(decoded)
            expect(adapter.validate_event(events.fetch(0), skip_record_validation: true).failure).to be_nil
          end
          decoded = build_decoder(results, path).decode(envelope_bytes(pool, product: {destination_id: "d1", schedule: {period: {}}}))
          events, = adapter.events_from(decoded)
          expect(adapter.validate_event(events.fetch(0), skip_record_validation: true).failure.message)
            .to include("record.schedule.created", "rollover index")
          decoded = build_decoder(results, path).decode(envelope_bytes(pool, product: {destination_id: "d1", schedule: {period: {created: "2024-02-29"}}}))
          events, = adapter.events_from(decoded)
          expect(adapter.validate_event(events.fetch(0), skip_record_validation: true).failure).to be_nil
        end
      end

      it "requires a nested rollover timestamp when its optional parent is absent" do
        results = define_proto_schema_results do |schema|
          schema.interface_type("Period") { |type| type.field "created", "Date", name_in_index: "private_created" }
          schema.object_type("ConcretePeriod") do |type|
            type.implements "Period"
            type.field "created", "Date", name_in_index: "private_created"
          end
          schema.object_type("Product") do |type|
            type.field "id", "ID!"
            type.field "period", "Period", name_in_index: "private_period"
            type.index("products") { |index| index.rollover :yearly, "period.created" }
          end
        end
        with_compiled_proto(results) do |pool, path|
          adapter = IngestionAdapter.new(schema_artifacts: results)
          decoded = build_decoder(results, path).decode(envelope_bytes(pool, product: {}))
          events, = adapter.events_from(decoded)
          expect(adapter.validate_event(events.fetch(0), skip_record_validation: true).failure.message)
            .to include("record.period.created", "rollover index")
          decoded = build_decoder(results, path).decode(envelope_bytes(pool, product: {period: {concrete_period: {created: "2024-02-29"}}}))
          events, = adapter.events_from(decoded)
          expect(adapter.validate_event(events.fetch(0), skip_record_validation: true).failure).to be_nil
        end
      end

      it "retains integer width in nested wrappers and maps public renames to the current default index destination" do
        original = define_proto_schema_results do |schema|
          schema.object_type("Product") do |t|
            t.field "id", "ID!"
            t.field "old_count", "[[JsonSafeLong]]"
            t.index "products"
          end
        end
        current = define_proto_schema_results(original) do |schema|
          schema.object_type("Product") do |t|
            t.field "id", "ID!"
            t.field("count", "[[Int]]") { |f| f.renamed_from "old_count" }
            t.index "products"
          end
        end
        with_compiled_proto(original) do |publisher, _|
          with_compiled_proto(current) do |_, path|
            adapter = IngestionAdapter.new(schema_artifacts: current)
            [INT_MAX, INT_MAX + 1].each do |number|
              bytes = envelope_bytes(publisher, product: {old_count: [{values: [number]}]})
              events, = adapter.events_from(build_decoder(current, path).decode(bytes))
              result = adapter.validate_event(events.fetch(0), skip_record_validation: true)
              if number == INT_MAX
                expect(result.failure).to be_nil
                expect(result.record_preparer.prepare_for_index("Product", result.event.record, nil))
                  .to include("count" => [[INT_MAX]]).and exclude("old_count")
              else
                expect(result.failure.message).to include("record.count[0][0]", "valid Int")
              end
            end
          end
        end
      end

      it "resolves every historical public raw alias and ignores each alias after deletion" do
        original = define_proto_schema_results do |schema|
          schema.object_type("Product") do |t|
            t.field "id", "ID!"
            t.index "products"
          end
        end
        renamed = define_proto_schema_results(original) do |schema|
          schema.object_type("Item") do |t|
            t.renamed_from "Product"
            t.field "id", "ID!"
            t.index "products"
          end
        end
        current = define_proto_schema_results(renamed) do |schema|
          schema.object_type("Article") do |t|
            t.renamed_from "Item"
            t.field "id", "ID!"
            t.index "products"
          end
        end
        with_compiled_proto(current) do |_, path|
          %w[Product Item Article].each do |name|
            decoder = build_decoder(current, path, "format" => "raw")
            expect(decoder.decode_with_metadata("", metadata: {"eg_type" => name}).fetch(0).fetch("type")).to eq("Article")
          end
        end
        deleted = define_proto_schema_results(current) { |schema| schema.deleted_type "Article" }
        with_compiled_proto(deleted) do |_, path|
          decoder = build_decoder(deleted, path, "format" => "raw")
          %w[Product Item Article].each do |name|
            expect(decoder.decode_with_metadata("", metadata: {"eg_type" => name})).to be_empty
          end
        end
      end

      it "validates the canonical rules of renamed scalar types when general validation is sampled out" do
        results = define_proto_schema_results(type_name_overrides: {"JsonSafeLong" => "SafeLong"}) do |schema|
          schema.object_type("Product") do |t|
            t.field "id", "ID!"
            t.field "count", "SafeLong"
            t.index "products"
          end
        end
        with_compiled_proto(results) do |pool, path|
          events, = IngestionAdapter.new(schema_artifacts: results).events_from(build_decoder(results, path).decode(envelope_bytes(pool, product: {count: JSON_SAFE_LONG_MAX + 1})))
          result = IngestionAdapter.new(schema_artifacts: results).validate_event(events.fetch(0), skip_record_validation: true)
          expect(result.failure.message).to include("record.count", "valid SafeLong")
        end
      end

      def rollover_schema(prior = nil, renamed: false)
        define_proto_schema_results(prior) do |schema|
          schema.object_type("Product") do |t|
            t.field "id", "ID!"
            t.field(renamed ? "created" : "created_at", "Date!", name_in_index: "private_created") { |f| f.renamed_from "created_at" if renamed }
            t.index("products") { |i| i.rollover :yearly, renamed ? "created" : "created_at" }
          end
        end
      end

      def renamed_schema(prior = nil, renamed: false, declarations: true)
        define_proto_schema_results(prior) do |schema|
          schema.enum_type(renamed ? "State" : "Status") do |t|
            t.renamed_from "Status" if renamed && declarations
            t.value(renamed ? "ENABLED" : "ACTIVE") { |v| v.renamed_from "ACTIVE" if renamed && declarations }
          end
          schema.object_type(renamed ? "Cube" : "Box") do |t|
            t.renamed_from "Box" if renamed && declarations
            t.field(renamed ? "length" : "size", "Int") { |f| f.renamed_from "size" if renamed && declarations }
          end
          schema.union_type(renamed ? "Figure" : "Shape") do |t|
            t.renamed_from "Shape" if renamed && declarations
            t.subtypes(renamed ? "Cube" : "Box")
          end
          schema.object_type(renamed ? "Item" : "Product") do |t|
            t.renamed_from "Product" if renamed && declarations
            t.field "id", "ID!"
            t.field(renamed ? "name" : "full_name", "String", name_in_index: "private_name") { |f| f.renamed_from "full_name" if renamed && declarations }
            t.field "detail", renamed ? "Cube" : "Box"
            t.field "shape", renamed ? "Figure" : "Shape"
            t.field "status", renamed ? "State" : "Status"
            t.index "products"
          end
        end
      end

      def integer_schema(prior = nil, narrowed: false)
        define_proto_schema_results(prior) do |schema|
          type = narrowed ? "Int" : "JsonSafeLong"
          schema.object_type("Product") do |t|
            t.field "id", "ID!"
            t.field "quantity", type
            t.field "cube", "[[#{type}]]"
            t.index "products"
          end
        end
      end

      def enum_schema(prior = nil, syntax:, retired: false)
        define_proto_schema_results(prior) do |schema|
          schema.proto_schema_artifacts package_name: "elasticgraph", syntax: syntax
          schema.enum_type("Status") { |t| t.values(*(retired ? ["ACTIVE"] : ["ACTIVE", "RETIRED"])) }
          schema.object_type("Product") do |t|
            t.field "id", "ID!"
            t.field "status", "Status"
            t.field "statuses", "[Status]"
            t.index "products"
          end
        end
      end

      def deletion_schema(prior = nil, deleted: false)
        define_proto_schema_results(prior) do |schema|
          schema.object_type("Product") { |t|
            t.field "id", "ID!"
            t.field "name", "String"
            t.index "products"
          }
          if deleted
            schema.deleted_type "Removed"
          else
            schema.object_type("Removed") { |t|
              t.field "id", "ID!"
              t.field "name", "String"
              t.index "removed"
            }
          end
        end
      end

      def build_decoder(results, path, config = {})
        IndexingEventDecoder.new(config: {"descriptor_set_file" => path}.merge(config), schema_artifacts: results)
      end

      def envelope_bytes(pool, **records)
        envelope = pool.lookup("elasticgraph.ElasticGraphEventEnvelope").msgclass
        batch = pool.lookup("elasticgraph.ElasticGraphEventBatch").msgclass
        batch.encode(batch.new(events: [envelope.new(op: "upsert", id: "p1", version: 1, **records)]))
      end

      def batch_bytes(*envelopes)
        envelopes.map { |bytes| length_delimited_field(1, bytes) }.join.b
      end

      def length_delimited_field(number, bytes)
        varint((number << 3) | 2) + varint(bytes.bytesize) + bytes.b
      end

      def varint(value)
        bytes = []
        while value > 127
          bytes << ((value & 127) | 128)
          value >>= 7
        end
        (bytes << value).pack("C*")
      end
    end
  end
end
