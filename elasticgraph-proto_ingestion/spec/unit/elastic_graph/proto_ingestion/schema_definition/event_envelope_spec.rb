# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/proto_ingestion/schema_definition/schema"

module ElasticGraph
  module ProtoIngestion
    module SchemaDefinition
      RSpec.describe "Protobuf event envelope" do
        it "omits the envelope when no types are ingestible" do
          results = define_proto_schema_results { |schema| schema.object_type("Product") { |type| type.field "id", "ID!" } }
          expect(results.proto_schema).to eq("")
        end

        %w[proto2 proto3].each do |syntax|
          it "renders metadata, sorted record alternatives, and a batch using #{syntax}" do
            results = define_proto_schema_results do |schema|
              schema.proto_schema_artifacts package_name: "catalog", syntax: syntax
              %w[Pear Apple].each do |name|
                schema.object_type(name) do |type|
                  type.field "id", "ID!"
                  type.index name.downcase
                end
              end
            end

            expect(proto_type_def_from(results.proto_schema, "ElasticGraphEventEnvelope")).to eq(<<~PROTO.strip)
              message ElasticGraphEventEnvelope {
                optional string op = 1;
                optional string id = 2;
                optional int64 version = 3;
                map<string, google.protobuf.Timestamp> latency_timestamps = 4;

                oneof record {
                  .catalog.Apple apple = 5;
                  .catalog.Pear pear = 6;
                }
              }
            PROTO
          end
        end

        it "orders record alternatives by their stable field numbers rather than alphabetically" do
          prior = define_proto_schema_results do |schema|
            schema.object_type "Pear" do |type|
              type.field "id", "ID"
              type.index "pears"
            end
          end

          current = define_proto_schema_results(prior) do |schema|
            %w[Apple Pear].each do |name|
              schema.object_type(name) do |type|
                type.field "id", "ID"
                type.index name.downcase
              end
            end
          end

          envelope = proto_type_def_from(current.proto_schema, "ElasticGraphEventEnvelope")
          expect(envelope.lines.grep(/ = \d+;/).map(&:strip)).to eq([
            "optional string op = 1;",
            "optional string id = 2;",
            "optional int64 version = 3;",
            "map<string, google.protobuf.Timestamp> latency_timestamps = 4;",
            ".elasticgraph.Pear pear = 5;",
            ".elasticgraph.Apple apple = 6;"
          ])
        end

        it "reserves removed envelope variants and reuses their numbers when restored" do
          define_types = lambda do |schema, names|
            names.each do |name|
              schema.object_type(name) do |type|
                type.field "id", "ID"
                type.index name.downcase
              end
            end
          end

          old = define_proto_schema_results { |schema| define_types.call(schema, ["Apple", "Pear"]) }
          current = define_proto_schema_results(old) { |schema| define_types.call(schema, ["Pear"]) }
          expect(current.proto_schema).to include("reserved 5; // Previously used by apple.", "pear = 6;")

          restored = define_proto_schema_results(current) { |schema| define_types.call(schema, ["Pear", "Apple"]) }
          expect(restored.proto_schema).to include("apple = 5;", "pear = 6;").and exclude("reserved 5;")
        end

        %w[Op Id Version LatencyTimestamps Record].each do |name|
          it "rejects #{name} because its envelope field name is reserved" do
            expect {
              define_proto_schema_results do |schema|
                schema.object_type(name) do |type|
                  type.field "id", "ID!"
                  type.index "records"
                end
              end
            }.to raise_error(Errors::SchemaError,
              a_string_including(
                "Ingestible type `#{name}` maps to reserved protobuf envelope field",
                "Rename `#{name}` so its snake_case name does not conflict with a reserved envelope field."
              ))
          end
        end

        it "rejects type names that produce the same envelope field name" do
          expect {
            define_proto_schema_results do |schema|
              %w[MyProduct My_Product].each_with_index do |name, i|
                schema.object_type(name) do |type|
                  type.field "id", "ID!"
                  type.index "products#{i}"
                end
              end
            end
          }.to raise_error(Errors::SchemaError,
            "Ingestible types `MyProduct` and `My_Product` map to the same protobuf envelope field `my_product`. " \
            "Rename one of these types so their names remain distinct when converted to snake_case.")
        end
      end
    end
  end
end
