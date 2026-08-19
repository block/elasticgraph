# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/proto_ingestion/schema_definition/api_extension"

module ElasticGraph
  module ProtoIngestion
    module SchemaDefinition
      # Covers how field numbers and enum value numbers stay stable as the schema evolves, backed
      # by the `proto_field_numbers.yaml` mappings.
      RSpec.describe Schema, "stable field and enum value numbers" do
        it "assigns a new field the stored `next_number` rather than filling an earlier gap" do
          # A cursor with gaps below it can only arise from a hand-edited artifact, so this test
          # must seed raw mappings instead of results from a prior dump.
          results = define_proto_schema_results(proto_field_number_mappings: {
            "messages" => {
              "Account" => {
                "fields" => {
                  "id" => 7
                },
                "next_number" => 10
              }
            }
          }) do |s|
            s.object_type "Account" do |t|
              t.field "id", "ID"
              t.field "name", "String"
              t.index "accounts"
            end
          end

          expect(results.proto_schema).to include("string id = 7;", "string name = 10;")
          expect(proto_type_def_from(results.proto_schema, "Account")).to include("// Next field number: 11")
          expect(results.proto_field_number_mappings.dig("messages", "Account", "next_number")).to eq(11)
        end

        it "preserves proto field numbers when fields are re-ordered" do
          results1 = define_proto_schema_results do |s|
            s.object_type "Account" do |t|
              t.field "id", "ID"
              t.field "name", "String"
              t.field "age", "Int"
              t.index "accounts"
            end
          end

          expect(proto_type_def_from(results1.proto_schema, "Account")).to include(
            "string id = 1;", "string name = 2;", "int32 age = 3;"
          )

          results2 = define_proto_schema_results(results1) do |s|
            s.object_type "Account" do |t|
              t.field "age", "Int"
              t.field "id", "ID"
              t.field "name", "String"
              t.index "accounts"
            end
          end

          expect(proto_type_def_from(results2.proto_schema, "Account")).to include(
            "string id = 1;", "string name = 2;", "int32 age = 3;"
          )
          expect(results2.proto_field_number_mappings).to eq(results1.proto_field_number_mappings)
        end

        it "exposes generated field-number mappings as an artifact hash" do
          results = define_proto_schema_results do |s|
            s.object_type "Account" do |t|
              t.field "id", "ID"
              t.field "name", "String"
              t.index "accounts"
            end
          end

          expect(results.proto_field_number_mappings).to eq({
            "enums" => {},
            "messages" => {
              "Account" => {
                "fields" => {
                  "id" => 1,
                  "name" => 2
                },
                "next_number" => 3
              }
            }
          })
        end

        it "keeps a removed field's number reserved and restores it if the field is re-added" do
          results1 = define_proto_schema_results do |s|
            s.object_type "Account" do |t|
              t.field "id", "ID"
              t.field "legacy_field", "String"
              t.index "accounts"
            end
          end

          expect(results1.proto_schema).to include("string legacy_field = 2;")

          # `legacy_field` has been removed and `name` added since the mappings were dumped.
          results2 = define_proto_schema_results(results1) do |s|
            s.object_type "Account" do |t|
              t.field "id", "ID"
              t.field "name", "String"
              t.index "accounts"
            end
          end

          expect(results2.proto_schema).to include("string id = 1;", "string name = 3;")
          expect(results2.proto_schema).to include("reserved 2; // Previously used by legacy_field.")

          # `legacy_field` keeps its number reserved in the artifact so it is never reused.
          expect(results2.proto_field_number_mappings).to eq({
            "enums" => {},
            "messages" => {
              "Account" => {
                "fields" => {
                  "id" => 1,
                  "legacy_field" => 2,
                  "name" => 3
                },
                "next_number" => 4
              }
            }
          })

          # `legacy_field` is restored after the intermediate artifact has been dumped.
          results3 = define_proto_schema_results(results2) do |s|
            s.object_type "Account" do |t|
              t.field "id", "ID"
              t.field "legacy_field", "String"
              t.field "name", "String"
              t.index "accounts"
            end
          end

          expect(results3.proto_schema).to include(
            "string id = 1;", "string legacy_field = 2;", "string name = 3;", "// Next field number: 4"
          )
          expect(results3.proto_schema).not_to include("reserved 2;")
          expect(results3.proto_field_number_mappings).to eq(results2.proto_field_number_mappings)
        end

        it "keeps index field names out of the protobuf schema and field-number mappings" do
          results1 = define_proto_schema_results do |s|
            s.object_type "Widget" do |t|
              t.field "id", "ID"
              t.field "display_name", "String", name_in_index: "old_index_name"
              t.index "widgets"
            end
          end

          results2 = define_proto_schema_results(results1) do |s|
            s.object_type "Widget" do |t|
              t.field "id", "ID"
              t.field "display_name", "String", name_in_index: "new_index_name"
              t.index "widgets"
            end
          end

          expect(results1.proto_schema).to include("string display_name = 2;")
          expect(results1.proto_schema).not_to include("old_index_name")
          expect(results2.proto_schema).to eq(results1.proto_schema)

          expect(results2.proto_field_number_mappings.dig("messages", "Widget", "fields")).to eq({
            "id" => 1,
            "display_name" => 2
          })
        end

        it "preserves a field number across a public field rename" do
          results1 = define_proto_schema_results do |s|
            s.object_type "Account" do |t|
              t.field "full_name", "String"
              t.field "id", "ID"
              t.index "accounts"
            end
          end

          expect(results1.proto_schema).to include("string full_name = 1;")

          results2 = define_proto_schema_results(results1) do |s|
            s.object_type "Account" do |t|
              t.field "id", "ID"
              t.field "display_name", "String" do |f|
                f.renamed_from "full_name"
              end
              t.index "accounts"
            end
          end

          expect(results2.proto_schema).to include("string id = 2;", "string display_name = 1;")
          expect(results2.proto_schema).not_to include("reserved 1;")
          expect(results2.proto_field_number_mappings).to eq({
            "enums" => {},
            "messages" => {
              "Account" => {
                "fields" => {
                  "id" => 2,
                  "display_name" => 1
                },
                "next_number" => 3
              }
            }
          })
        end

        it "preserves enum value numbers as the enum evolves, reserving removed values' numbers" do
          results1 = define_proto_schema_results do |s|
            s.enum_type "Status" do |t|
              t.values "ACTIVE", "PAUSED", "INACTIVE"
            end

            s.object_type "Account" do |t|
              t.field "id", "ID"
              t.field "status", "Status"
              t.index "accounts"
            end
          end

          expect(proto_type_def_from(results1.proto_schema, "Status")).to include(
            "STATUS_ACTIVE = 1;",
            "STATUS_PAUSED = 2;",
            "STATUS_INACTIVE = 3;",
            "// Next value number: 4"
          )

          # `PAUSED` has been removed and `ARCHIVED` added since the mappings were dumped.
          results2 = define_proto_schema_results(results1) do |s|
            s.enum_type "Status" do |t|
              t.values "ACTIVE", "INACTIVE", "ARCHIVED"
            end

            s.object_type "Account" do |t|
              t.field "id", "ID"
              t.field "status", "Status"
              t.index "accounts"
            end
          end

          expect(proto_type_def_from(results2.proto_schema, "Status")).to include(
            "STATUS_ACTIVE = 1;",
            "STATUS_INACTIVE = 3;",
            "STATUS_ARCHIVED = 4;",
            "reserved 2; // Previously used by PAUSED.",
            "// Next value number: 5"
          )

          # `PAUSED` keeps its number reserved in the artifact so it is never reused for a new value.
          expect(results2.proto_field_number_mappings.fetch("enums")).to eq({
            "Status" => {
              "values" => {
                "ACTIVE" => 1,
                "PAUSED" => 2,
                "INACTIVE" => 3,
                "ARCHIVED" => 4
              },
              "next_number" => 5
            }
          })
        end

        it "preserves stable field numbers for oneof alternatives as subtypes are added and removed" do
          results1 = define_proto_schema_results do |s|
            ["Truck", "Car", "Bike"].each do |type_name|
              s.object_type type_name do |t|
                t.field "id", "ID"
              end
            end

            s.union_type "Vehicle" do |t|
              t.subtypes "Truck", "Car", "Bike"
              t.index "vehicles"
            end
          end

          expect(proto_type_def_from(results1.proto_schema, "Vehicle")).to include(
            "Truck truck = 1;", "Car car = 2;", "Bike bike = 3;"
          )

          # `Truck` has been removed and `Scooter` added since the mappings were dumped.
          results2 = define_proto_schema_results(results1) do |s|
            ["Car", "Bike", "Scooter"].each do |type_name|
              s.object_type type_name do |t|
                t.field "id", "ID"
              end
            end

            s.union_type "Vehicle" do |t|
              t.subtypes "Car", "Bike", "Scooter"
              t.index "vehicles"
            end
          end

          vehicle = proto_type_def_from(results2.proto_schema, "Vehicle")
          expect(vehicle).to include(
            "Car car = 2;",
            "Bike bike = 3;",
            "Scooter scooter = 4;",
            "reserved 1; // Previously used by truck."
          )

          # `truck` keeps its number reserved in the artifact so it is never reused.
          expect(results2.proto_field_number_mappings.fetch("messages").fetch("Vehicle")).to eq({
            "fields" => {
              "truck" => 1,
              "car" => 2,
              "bike" => 3,
              "scooter" => 4
            },
            "next_number" => 5
          })
        end
      end
    end
  end
end
