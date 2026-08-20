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
      # Covers the `syntax:` and `header_lines:` options of `proto_schema_artifacts`.
      RSpec.describe Schema, "proto syntax and header lines" do
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

        it "omits the field label on `oneof` alternatives under `proto2`, which protoc forbids from carrying one" do
          proto = define_proto_schema do |s|
            s.proto_schema_artifacts package_name: "elasticgraph", syntax: :proto2

            s.object_type "Car" do |t|
              t.implements "Vehicle"
              t.field "id", "ID"
            end

            s.object_type "Bike" do |t|
              t.implements "Vehicle"
              t.field "id", "ID"
            end

            s.interface_type "Vehicle" do |t|
              t.field "id", "ID"
              t.index "vehicles"
            end
          end

          # The alternatives carry no `optional`, unlike the `optional string id` fields on the
          # concrete messages below, which do get a label under proto2.
          expect(proto_type_def_from(proto, "Vehicle")).to eq(<<~PROTO.strip)
            message Vehicle {
              oneof value {
                .elasticgraph.Car car = 1;
                .elasticgraph.Bike bike = 2;
              }
              // Next field number: 3
            }
          PROTO

          expect(proto_type_def_from(proto, "Car")).to include("optional string id = 1;")
        end

        it "renders custom `header_lines` verbatim after the package declaration" do
          proto = define_proto_schema do |s|
            s.proto_schema_artifacts(
              package_name: "myapp.events.v1",
              header_lines: [
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
      end
    end
  end
end
