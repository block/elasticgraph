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
            }

            message Address {
              string street = 1;
              string city = 2;
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
            }
          PROTO
          expect(proto_type_def_from(proto, "Inventor")).to eq(<<~PROTO.strip)
            message Inventor {
              oneof value {
                .elasticgraph.Person person = 1;
                .elasticgraph.Company company = 2;
              }
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

        it "uses public field names in schema.proto when `name_in_index` differs" do
          proto = define_proto_schema do |s|
            s.object_type "Widget" do |t|
              t.field "id", "ID"
              t.field "display_name", "String", name_in_index: "display_name_in_index"
              t.index "widgets"
            end
          end

          widget = proto_type_def_from(proto, "Widget")
          expect(widget).to include("string display_name = 2;")
          expect(widget).not_to include("display_name_in_index")
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
