# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/proto_ingestion/schema_definition/wire_contracts"

module ElasticGraph
  module ProtoIngestion
    module SchemaDefinition
      RSpec.describe WireContracts do
        ["proto2", "proto3"].each do |syntax|
          it "reads scalar, enum, message, imported, and nested-list declarations in #{syntax}" do
            original = define_proto_schema_results do |schema|
              schema.proto_schema_artifacts package_name: "elasticgraph", syntax: syntax
              schema.enum_type("Status") { |type| type.values "ACTIVE" }
              schema.object_type("Details") { |type| type.field "name", "String" }
              schema.object_type "Account" do |type|
                type.field "id", "ID"
                type.field "scores", "[[[Int!]]!]"
                type.field "status", "Status"
                type.field("details", "[Details]") { |field| field.mapping type: "nested" }
                type.field "updated_at", "DateTime"
                type.index "accounts"
              end
            end

            contracts = WireContracts.new(original.proto_schema, "elasticgraph")
            [["string", 0], ["int32", 3], [".elasticgraph.Status", 0], [".elasticgraph.Details", 1], ["google.protobuf.Timestamp", 0]].each_with_index do |(proto_type, depth), index|
              expect { contracts.verify_and_record("Account", "renamed_#{index}", index + 1, proto_type, depth) }.not_to raise_error
              expect { contracts.verify_and_record("Account", "renamed_#{index}", index + 1, proto_type, depth + 1) }.to raise_error(Errors::SchemaError, a_string_including("list depth #{depth}"))
            end
            expect(contracts.retired_contract_comments).not_to include("Account.")
          end
        end

        it "rejects incompatible types and list depths before and after field removal" do
          old = account_schema(nil, "Int")
          removed = account_schema(old, nil)
          removed_again = account_schema(removed, nil)
          expect(removed_again.proto_schema).to eq(removed.proto_schema)
          expect(removed.proto_schema).to include("reserved 2;", "// Retained wire contract: Account.score = 2; int32 (list depth 0).")
          [old, removed_again].each do |prior|
            ["String", "JsonSafeLong", "[Int]", "[[Int]]"].each do |field_type|
              expect { account_schema(prior, field_type) }.to raise_error(Errors::SchemaError, a_string_including("Account.score", "retained int32", "Use a new field name"))
            end
          end
          restored = account_schema(removed_again, "Int!")
          expect(restored.proto_schema).to include("int32 score = 2;")
          expect(restored.proto_schema).not_to include("Retained wire contract: Account.score", "reserved 2;")
          expect(restored.proto_field_number_mappings).to eq(old.proto_field_number_mappings)
        end

        it "retains contracts beneath removed list wrappers" do
          old = account_schema(nil, "[[Int]]")
          removed = account_schema(old, nil)
          expect(removed.proto_schema).not_to include("message ScoreList")
          expect(removed.proto_schema).to include("Account.score = 2; int32 (list depth 2).")
          expect { account_schema(removed, "[[String]]") }.to raise_error(Errors::SchemaError, a_string_including("retained int32 (list depth 2)"))
          expect(account_schema(removed, "[[Int]]").proto_schema).to eq(old.proto_schema)
        end

        it "checks the number's contract across a rename" do
          old = account_schema(nil, "Int")
          expect {
            define_proto_schema_results(old) do |schema|
              schema.object_type "Account" do |type|
                type.field "id", "ID"
                type.field("points", "String") { |field| field.renamed_from "score" }
                type.index "accounts"
              end
            end
          }.to raise_error(Errors::SchemaError, a_string_including("Account.points", "retained int32"))
        end

        it "checks oneof alternatives and envelope fields" do
          old = define_proto_schema_results do |schema|
            schema.object_type("Car") { |type| type.field "id", "ID" }
            schema.union_type "Vehicle" do |type|
              type.subtypes "Car"
              type.index "vehicles"
            end
          end
          contracts = WireContracts.new(old.proto_schema, "elasticgraph")
          expect { contracts.verify_and_record("Vehicle", "car", 1, ".elasticgraph.Truck", 0) }.to raise_error(Errors::SchemaError, a_string_including("retained .elasticgraph.Car"))
          vehicle_number = old.proto_field_number_mappings.dig("messages", "ElasticGraphEventEnvelope", "fields", "vehicle")
          expect { contracts.verify_and_record("ElasticGraphEventEnvelope", "vehicle", vehicle_number, ".elasticgraph.Car", 0) }.to raise_error(Errors::SchemaError, a_string_including("retained .elasticgraph.Vehicle"))
          expect { contracts.verify_and_record("ElasticGraphEventEnvelope", "latency_timestamps", 4, "map<string, google.protobuf.Timestamp>", 1) }.not_to raise_error
        end

        it "retains contracts when a whole message disappears, including when all indexed types disappear" do
          old = account_schema(nil, "Int")
          removed = define_proto_schema_results(old) do |schema|
            schema.object_type "Other" do |type|
              type.field "id", "ID"
              type.index "others"
            end
          end
          expect(removed.proto_schema).not_to include("message Account")
          expect(removed.proto_schema).to include("Account.score = 2; int32 (list depth 0).")
          expect { account_schema(removed, "String") }.to raise_error(Errors::SchemaError, a_string_including("retained int32"))

          empty = define_proto_schema_results(old) do |schema|
            schema.on_root_query_type do |type|
              type.field("value", "String") { |field| field.resolve_with :object_without_lookahead }
            end
          end
          expect(empty.proto_schema).to include("Account.score = 2; int32 (list depth 0).")
          expect { account_schema(empty, "String") }.to raise_error(Errors::SchemaError, a_string_including("retained int32"))
        end

        it "compares list wrappers using the previous schema's package" do
          old = define_proto_schema_results do |schema|
            schema.proto_schema_artifacts package_name: "old_package"
            schema.object_type "Account" do |type|
              type.field "id", "ID"
              type.field "score", "[[Int]]"
              type.index "accounts"
            end
          end
          contracts = WireContracts.new(old.proto_schema, "elasticgraph")
          expect { contracts.verify_and_record("Account", "score", 2, "int32", 2) }.not_to raise_error
          expect { contracts.verify_and_record("Account", "score", 2, "int32", 1) }.to raise_error(Errors::SchemaError, a_string_including("retained int32 (list depth 2)"))
        end

        def account_schema(prior, field_type)
          define_proto_schema_results(prior) do |schema|
            schema.object_type "Account" do |type|
              type.field "id", "ID"
              type.field "score", field_type if field_type
              type.index "accounts"
            end
          end
        end
      end
    end
  end
end
