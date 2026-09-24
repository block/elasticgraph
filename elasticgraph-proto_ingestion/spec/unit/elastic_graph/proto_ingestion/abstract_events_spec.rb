# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/proto_ingestion/indexing_event_decoder"
require "elastic_graph/spec_support/compiled_proto_support"

module ElasticGraph
  module ProtoIngestion
    RSpec.describe "Abstract protobuf events", :builds_indexer, :capture_logs do
      include CompiledProtoSupport

      let(:results) do
        define_proto_schema_results do |schema|
          schema.object_type("Person") do |t|
            t.field "id", "ID!"
            t.field "name", "String"
          end
          schema.object_type("Company") do |t|
            t.field "id", "ID!"
            t.field "name", "String"
          end
          schema.union_type("Inventor") do |t|
            t.subtypes "Person", "Company"
            t.index "inventors"
          end
        end
      end

      it "routes indexed union wrappers to the selected concrete type" do
        with_compiled_proto(results) do |pool, path|
          envelope = pool.lookup("elasticgraph.ElasticGraphEventEnvelope").msgclass
          batch = pool.lookup("elasticgraph.ElasticGraphEventBatch").msgclass
          decoder = IndexingEventDecoder.new(config: {"descriptor_set_file" => path}, schema_artifacts: results)
          event = decoder.decode(batch.encode(batch.new(events: [envelope.new(op: "upsert", id: "p1", version: 1,
            record_inventor: {person: {name: "Person"}})]))).fetch(0)
          result = build_result(results, event)
          expect(result.failed_event_error).to be_nil
          expect(result.operations.map(&:prepared_record)).to contain_exactly(a_hash_including("id" => "p1", "name" => "Person", "__typename" => "Person"))
        end
      end

      it "rejects an abstract record without a selected subtype" do
        with_compiled_proto(results) do |pool, _|
          record = pool.lookup("elasticgraph.Inventor").msgclass.new
          result = build_result(results, event_for(record))
          expect(result.failed_event_error.message).to include("An abstract record must select a concrete subtype")
        end
      end

      it "rejects a canonical record with an unknown subtype even when record validation is sampled out" do
        indexer = build_indexer(schema_artifacts: results)
        factory = indexer.operation_factory.with(
          skip_record_validation_percents_by_type: {"Inventor" => 100}
        )
        event = indexer.ingestion_adapters_by_format.fetch("proto").events_from([event_for({"__typename" => "Unknown"})]).first.fetch(0)
        result = factory.build(event)
        expect(result.failed_event_error.message).to include("The selected subtype is not ingestible")
      end

      it "preserves update targets attached to an abstract source type" do
        results = define_proto_schema_results do |schema|
          schema.interface_type("Inventor") do |t|
            t.field "id", "ID!"
            t.field "product_id", "ID!"
            t.field "name", "String"
          end
          schema.object_type("Person") do |t|
            t.implements "Inventor"
            t.field "id", "ID!"
            t.field "product_id", "ID!"
            t.field "name", "String"
          end
          schema.object_type("Product") do |t|
            t.field "id", "ID!"
            t.relates_to_one "inventor", "Inventor", via: "product_id", dir: :in, indexing_only: true
            t.field("inventor_name", "String") { |f| f.sourced_from "inventor", "name" }
            t.index("products") { |i| i.has_had_multiple_sources! }
          end
        end
        with_compiled_proto(results) do |pool, _|
          record = pool.lookup("elasticgraph.Inventor").msgclass.new(person: {product_id: "product1", name: "Person"})
          result = build_result(results, event_for(record))
          expect(result.failed_event_error).to be_nil
          expect(result.operations.map(&:doc_id)).to eq(["product1"])
          expect(result.operations.map { |op| op.event.type }).to eq(["Inventor"])
        end
      end

      def event_for(record)
        {"op" => "upsert", "type" => "Inventor", "id" => "p1", "version" => 1, "ingestion_format" => "proto", "record" => record}
      end

      def build_result(results, decoded_event)
        indexer = build_indexer(schema_artifacts: results)
        event = indexer.ingestion_adapters_by_format.fetch("proto").events_from([decoded_event]).first.fetch(0)
        indexer.operation_factory.build(event)
      end
    end
  end
end
