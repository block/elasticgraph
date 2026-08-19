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
      # Covers how indexed interface and union types become `oneof` wrapper messages.
      RSpec.describe Schema, "abstract types" do
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
      end
    end
  end
end
