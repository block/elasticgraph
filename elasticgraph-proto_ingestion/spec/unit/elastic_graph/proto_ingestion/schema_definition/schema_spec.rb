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
      RSpec.describe Schema do
        it "generates a proto schema from indexed types" do
          proto = define_proto_schema do |s|
            s.object_type "Account" do |t|
              t.documentation "An account in the system.\n\n"
              t.field "id", "ID" do |f|
                f.documentation "The account's unique identifier."
              end
              t.field "status", "Status"
              t.field "address", "Address"
              t.field "tags", "[String!]!"
              t.field "display_name", "String", graphql_only: true
              t.index "accounts"
            end

            s.object_type "Address" do |t|
              t.field "street", "String"
              t.field "city", "String"
            end

            s.enum_type "Status" do |t|
              t.documentation "The status of an account.\n\nUsed when ingesting accounts."
              t.value "ACTIVE" do |v|
                v.documentation "The account is active."
              end
              t.value "INACTIVE"
            end
          end

          expect(proto).to eq(<<~PROTO)
            syntax = "proto3";

            package elasticgraph;

            // An account in the system.
            message Account {
              // The account's unique identifier.
              string id = 1;
              .elasticgraph.Status status = 2;
              .elasticgraph.Address address = 3;
              repeated string tags = 4;
              // Next field number: 5
            }

            message Address {
              string street = 1;
              string city = 2;
              // Next field number: 3
            }

            // The status of an account.
            //
            // Used when ingesting accounts.
            enum Status {
              // The default value when no enum value has been explicitly set. Do not use this value.
              // See https://protobuf.dev/programming-guides/proto3/#enum-default.
              STATUS_UNSPECIFIED = 0;
              // The account is active.
              STATUS_ACTIVE = 1;
              STATUS_INACTIVE = 2;
              // Next value number: 3
            }
          PROTO
        end

        it "sorts enum and message definitions together alphabetically" do
          proto = define_proto_schema do |s|
            s.enum_type "Zulu" do |t|
              t.value "LAST"
            end

            s.object_type "Yak" do |t|
              t.field "id", "ID"
            end

            s.enum_type "Beta" do |t|
              t.value "SECOND"
            end

            s.object_type "Alpha" do |t|
              t.field "id", "ID"
              t.field "beta", "Beta"
              t.field "yak", "Yak"
              t.field "zulu", "Zulu"
              t.index "alphas"
            end
          end

          expect(proto.scan(/^(?:enum|message) (\w+) \{/).flatten).to eq(%w[Alpha Beta Yak Zulu])
        end

        it "emits proto2 syntax with an explicit label on every field when `syntax: :proto2`" do
          proto = define_proto_schema do |s|
            s.proto_schema_artifacts package_name: "elasticgraph", syntax: :proto2

            s.enum_type "Status" do |t|
              t.values "ACTIVE", "INACTIVE"
            end

            s.object_type "Account" do |t|
              t.field "id", "ID"
              t.field "status", "Status"
              t.field "tags", "[String!]!"
              t.index "accounts"
            end
          end

          expect(proto).to start_with(%(syntax = "proto2";))
          expect(proto_type_def_from(proto, "Account")).to include(
            "optional string id = 1;",
            "optional .elasticgraph.Status status = 2;",
            "repeated string tags = 3;"
          )
        end

        it "renders custom `headers` verbatim after the package declaration" do
          proto = define_proto_schema do |s|
            s.proto_schema_artifacts(
              package_name: "myapp.events.v1",
              headers: [
                %(option java_package = "com.myapp.events";),
                "option java_multiple_files = true;"
              ]
            )

            s.object_type "Account" do |t|
              t.field "id", "ID"
              t.index "accounts"
            end
          end

          expect(proto).to include(<<~PROTO)
            package myapp.events.v1;

            option java_package = "com.myapp.events";
            option java_multiple_files = true;

            message Account {
          PROTO
        end

        it "generates oneof wrappers for indexed interface and union types" do
          proto = define_proto_schema do |s|
            s.object_type "Car" do |t|
              t.implements "Vehicle"
              t.field "id", "ID"
              t.field "doors", "Int"
            end

            s.object_type "Bike" do |t|
              t.implements "Vehicle"
              t.field "id", "ID"
              t.field "gears", "Int"
            end

            s.interface_type "Vehicle" do |t|
              t.field "id", "ID"
              t.index "vehicles"
            end

            s.object_type "Person" do |t|
              t.field "id", "ID"
              t.field "name", "String"
            end

            s.object_type "Company" do |t|
              t.field "id", "ID"
              t.field "stock_ticker", "String"
            end

            s.union_type "Inventor" do |t|
              t.subtypes "Person", "Company"
              t.index "inventors"
            end
          end

          expect(proto_type_def_from(proto, "Vehicle")).to eq(<<~PROTO.strip)
            message Vehicle {
              oneof value {
                .elasticgraph.Car car = 1;
                .elasticgraph.Bike bike = 2;
              }
              // Next field number: 3
            }
          PROTO
          expect(proto_type_def_from(proto, "Inventor")).to eq(<<~PROTO.strip)
            message Inventor {
              oneof value {
                .elasticgraph.Person person = 1;
                .elasticgraph.Company company = 2;
              }
              // Next field number: 3
            }
          PROTO
          expect(proto_type_def_from(proto, "Car")).to include("string id = 1;", "int32 doors = 2;")
          expect(proto_type_def_from(proto, "Bike")).to include("string id = 1;", "int32 gears = 2;")
          expect(proto_type_def_from(proto, "Person")).to include("string id = 1;", "string name = 2;")
          expect(proto_type_def_from(proto, "Company")).to include("string id = 1;", "string stock_ticker = 2;")
          expect(proto_type_def_from(proto, "Missing")).to be_nil
          expect(proto).not_to include("__typename")
        end

        it "flattens nested interfaces" do
          proto = define_proto_schema do |s|
            s.object_type "Car" do |t|
              t.implements "MotorVehicle"
              t.field "id", "ID"
            end

            s.interface_type "MotorVehicle" do |t|
              t.implements "Vehicle"
              t.field "id", "ID"
            end

            s.interface_type "Vehicle" do |t|
              t.field "id", "ID"
              t.index "vehicles"
            end
          end

          expect(proto_type_def_from(proto, "Vehicle")).to eq(<<~PROTO.strip)
            message Vehicle {
              oneof value {
                .elasticgraph.Car car = 1;
              }
              // Next field number: 2
            }
          PROTO
          expect(proto_type_def_from(proto, "Car")).to include("string id = 1;")
          expect(proto_type_def_from(proto, "MotorVehicle")).to be_nil
        end

        it "snake-cases multiword oneof alternatives" do
          proto = define_proto_schema do |s|
            s.object_type "DeliveryVehicle" do |t|
              t.implements "Vehicle"
              t.field "id", "ID"
            end

            s.interface_type "Vehicle" do |t|
              t.field "id", "ID"
              t.index "vehicles"
            end
          end

          expect(proto_type_def_from(proto, "Vehicle")).to eq(<<~PROTO.strip)
            message Vehicle {
              oneof value {
                .elasticgraph.DeliveryVehicle delivery_vehicle = 1;
              }
              // Next field number: 2
            }
          PROTO
        end

        it "rejects lists of lists" do
          expect {
            define_proto_schema do |s|
              s.object_type "Matrix" do |t|
                t.field "id", "ID"
                t.field "values", "[[Float!]!]!"
                t.index "matrices"
              end
            end
          }.to raise_error(Errors::SchemaError, a_string_including(
            "Field `Matrix.values` has type `[[Float!]!]!`",
            "Protocol Buffers cannot represent lists of lists directly",
            "at most one list level"
          ))
        end

        it "uses custom proto scalar mappings" do
          proto = define_proto_schema do |s|
            s.scalar_type "CustomTimestamp" do |t|
              t.mapping type: "date"
              t.protobuf type: "int64"
            end

            s.object_type "Event" do |t|
              t.field "id", "ID"
              t.field "occurred_at", "CustomTimestamp"
              t.index "events"
            end
          end

          expect(proto_type_def_from(proto, "Event")).to include("int64 occurred_at = 2;")
        end

        it "maps `DateTime` fields to `google.protobuf.Timestamp`, importing its proto file once" do
          proto = define_proto_schema do |s|
            s.object_type "Event" do |t|
              t.field "id", "ID"
              t.field "created_at", "DateTime"
              t.field "updated_at", "DateTime"
              t.index "events"
            end
          end

          expect(proto).to eq(<<~PROTO)
            syntax = "proto3";

            package elasticgraph;

            import "google/protobuf/timestamp.proto";

            message Event {
              string id = 1;
              google.protobuf.Timestamp created_at = 2;
              google.protobuf.Timestamp updated_at = 3;
              // Next field number: 4
            }
          PROTO
        end

        it "sorts and de-duplicates imports shared by distinct protobuf types" do
          proto = define_proto_schema do |s|
            s.scalar_type "FirstZType" do |t|
              t.mapping type: "keyword"
              t.protobuf type: "example.FirstZType", import: "z/types.proto"
            end

            s.scalar_type "SecondZType" do |t|
              t.mapping type: "keyword"
              t.protobuf type: "example.SecondZType", import: "z/types.proto"
            end

            s.scalar_type "AType" do |t|
              t.mapping type: "keyword"
              t.protobuf type: "example.AType", import: "a/types.proto"
            end

            s.object_type "Event" do |t|
              t.field "id", "ID"
              t.field "first_z", "FirstZType"
              t.field "second_z", "SecondZType"
              t.field "a", "AType"
              t.index "events"
            end
          end

          expect(proto.lines.grep(/\Aimport /).map(&:chomp)).to eq([
            %(import "a/types.proto";),
            %(import "z/types.proto";)
          ])
        end

        it "renders format comments on fields whose scalar type documents one" do
          proto = define_proto_schema do |s|
            s.object_type "Person" do |t|
              t.field "id", "ID"
              t.field "birth_date", "Date"
              t.index "people"
            end
          end

          expect(proto).to include(
            %(string birth_date = 2; // ISO 8601 date, e.g. "2024-11-25")
          )
        end

        it "supports `import:` and `comment:` on custom scalar types" do
          proto = define_proto_schema do |s|
            s.scalar_type "Money" do |t|
              t.mapping type: "keyword"
              t.protobuf type: "myapp.types.Money", import: "myapp/types/money.proto", comment: "amount + currency"
            end

            s.object_type "Order" do |t|
              t.field "id", "ID"
              t.field "total", "Money"
              t.index "orders"
            end
          end

          expect(proto).to include('import "myapp/types/money.proto";')
          expect(proto).to include("myapp.types.Money total = 2; // amount + currency")
        end

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

        it "renders independently each time it is called" do
          results = define_proto_schema_results do |s|
            s.object_type "Account" do |t|
              t.field "id", "ID"
              t.index "accounts"
            end
          end

          generator = Schema.new(
            state: results.state,
            all_types: results.send(:all_types),
            package_name: "elasticgraph"
          )

          first_generation = generator.to_proto

          second_generation = generator.to_proto
          expect(second_generation).to eq(first_generation)
          expect(second_generation).not_to be(first_generation)
        end

        it "raises when a custom scalar is defined without a protobuf type" do
          expect {
            define_proto_schema do |s|
              s.scalar_type "UnconfiguredScalar" do |t|
                t.mapping type: "keyword"
              end
            end
          }.to raise_error(Errors::SchemaError, a_string_including(
            "Protobuf type not configured for scalar type `UnconfiguredScalar`.",
            "call `protobuf type:"
          ))
        end

        it "does not require a protobuf type for GraphQL-only scalars" do
          proto = define_proto_schema do |s|
            s.scalar_type "GraphQLOnlyScalar" do |t|
              t.mapping type: "keyword"
              t.graphql_only true
            end
          end

          expect(proto).to eq("")
        end

        it "resolves proto field types for built-in scalars that are renamed via `type_name_overrides`" do
          proto = define_proto_schema(type_name_overrides: {"JsonSafeLong" => "BigNumber"}) do |s|
            s.object_type "Account" do |t|
              t.field "id", "ID"
              t.field "amount", "BigNumber"
              t.index "accounts"
            end
          end

          expect(proto_type_def_from(proto, "Account")).to include("int64 amount = 2;")
        end

        it "prefixes enum values" do
          proto = define_proto_schema do |s|
            s.enum_type "Command" do |t|
              t.values "START", "STOP"
            end

            s.object_type "Request" do |t|
              t.field "id", "ID"
              t.field "command", "Command"
              t.index "requests"
            end
          end

          expect(proto_type_def_from(proto, "Command")).to include("COMMAND_START = 1;", "COMMAND_STOP = 2;")
        end

        it "uses source field names even when they are contextual protobuf keywords" do
          proto = define_proto_schema do |s|
            s.object_type "Request" do |t|
              t.field "id", "ID"
              t.field "package", "String"
              t.index "requests"
            end
          end

          expect(proto_type_def_from(proto, "Request")).to include("string package = 2;")
        end
      end
    end
  end
end
