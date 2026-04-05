# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/protobuf/schema_definition/api_extension"

module ElasticGraph
  module Protobuf
    module SchemaDefinition
      RSpec.describe Schema, :proto_schema do
        it "generates a proto schema from indexed types" do
          results = define_proto_schema do |s|
            s.enum_type "Status" do |t|
              t.values "ACTIVE", "INACTIVE"
            end

            s.object_type "Address" do |t|
              t.field "street", "String"
              t.field "city", "String"
            end

            s.object_type "Account" do |t|
              t.field "id", "ID"
              t.field "status", "Status"
              t.field "address", "Address"
              t.field "tags", "[String!]!"
              t.index "accounts"
            end
          end

          expect(proto_schema_from(results)).to eq(<<~PROTO)
            syntax = "proto3";

            package elasticgraph;

            enum Status {
              STATUS_UNSPECIFIED = 0;
              STATUS_ACTIVE = 1;
              STATUS_INACTIVE = 2;
            }

            message Account {
              string id = 1;
              Status status = 2;
              Address address = 3;
              repeated string tags = 4;
            }

            message Address {
              string street = 1;
              string city = 2;
            }
          PROTO
        end

        it "generates wrapper messages for nested lists" do
          results = define_proto_schema do |s|
            s.object_type "Matrix" do |t|
              t.field "id", "ID"
              t.field "values", "[[Float!]!]!"
              t.index "matrices"
            end
          end

          expect(proto_schema_from(results)).to eq(<<~PROTO)
            syntax = "proto3";

            package elasticgraph;

            message Matrix {
              string id = 1;
              repeated MatrixValuesListLevel1 values = 2;
            }

            message MatrixValuesListLevel1 {
              repeated double values = 1;
            }
          PROTO
        end

        it "uses custom proto scalar mappings" do
          results = define_proto_schema do |s|
            s.scalar_type "CustomTimestamp" do |t|
              t.mapping type: "date"
              t.json_schema type: "string", format: "date-time"
              t.proto_field type: "int64"
            end

            s.object_type "Event" do |t|
              t.field "id", "ID"
              t.field "occurred_at", "CustomTimestamp"
              t.index "events"
            end
          end

          expect(proto_schema_from(results)).to include("int64 occurred_at = 2;")
        end

        it "infers scalar mappings from json_schema type" do
          results = define_proto_schema do |s|
            s.scalar_type "EmailAddress" do |t|
              t.mapping type: "keyword"
              t.json_schema type: "string", format: "email"
            end

            s.object_type "User" do |t|
              t.field "id", "ID"
              t.field "email", "EmailAddress"
              t.index "users"
            end
          end

          expect(proto_schema_from(results)).to include("string email = 2;")
        end

        it "prefers explicit proto_field over inferred mapping" do
          results = define_proto_schema do |s|
            s.scalar_type "UnixTimestamp" do |t|
              t.mapping type: "long"
              t.json_schema type: "integer"
              t.proto_field type: "fixed64"
            end

            s.object_type "Event" do |t|
              t.field "id", "ID"
              t.field "occurred_at", "UnixTimestamp"
              t.index "events"
            end
          end

          expect(proto_schema_from(results)).to include("fixed64 occurred_at = 2;")
        end

        it "can assign field numbers from configured mappings" do
          results = define_proto_schema do |s|
            s.configure_proto_field_number_mappings(
              {
                "messages" => {
                  "Account" => {
                    "id" => 10,
                    "name" => 2
                  }
                }
              },
              enforce: true
            )

            s.object_type "Account" do |t|
              t.field "id", "ID"
              t.field "name", "String"
              t.index "accounts"
            end
          end

          generated = proto_schema_from(results)
          expect(generated).to include("string id = 10;")
          expect(generated).to include("string name = 2;")
        end

        it "assigns new field numbers after mapped values when mappings are partial" do
          results = define_proto_schema do |s|
            s.configure_proto_field_number_mappings(
              {
                "messages" => {
                  "Account" => {
                    "id" => 1
                  }
                }
              },
              enforce: true
            )

            s.object_type "Account" do |t|
              t.field "id", "ID"
              t.field "name", "String"
              t.index "accounts"
            end
          end

          expect(proto_schema_from(results)).to include("string name = 2;")
        end

        it "exposes generated field-number mappings as an artifact hash" do
          results = define_proto_schema do |s|
            s.object_type "Account" do |t|
              t.field "id", "ID"
              t.field "name", "String"
              t.index "accounts"
            end
          end

          expect(results.proto_field_number_mappings).to eq({
            "messages" => {
              "Account" => {
                "fields" => {
                  "id" => 1,
                  "name" => 2
                }
              }
            }
          })
        end

        it "preserves reserved numbers for removed fields and allocates new numbers above them" do
          results = define_proto_schema do |s|
            s.configure_proto_field_number_mappings(
              {
                "messages" => {
                  "Account" => {
                    "id" => 1,
                    "legacyField" => 2
                  }
                }
              }
            )

            s.object_type "Account" do |t|
              t.field "id", "ID"
              t.field "name", "String"
              t.index "accounts"
            end
          end

          generated = proto_schema_from(results)
          expect(generated).to include("string id = 1;")
          expect(generated).to include("string name = 3;")

          expect(results.proto_field_number_mappings).to eq({
            "messages" => {
              "Account" => {
                "fields" => {
                  "id" => 1,
                  "legacyField" => 2,
                  "name" => 3
                }
              }
            }
          })
        end

        it "uses public field names in schema.proto and stores name_in_index overrides in the mapping artifact" do
          results = define_proto_schema do |s|
            s.object_type "Widget" do |t|
              t.field "id", "ID"
              t.field "display_name", "String", name_in_index: "displayName"
              t.index "widgets"
            end
          end

          expect(proto_schema_from(results)).to include("string display_name = 2;")
          expect(proto_schema_from(results)).not_to include("displayName")

          expect(results.proto_field_number_mappings).to eq({
            "messages" => {
              "Widget" => {
                "fields" => {
                  "id" => 1,
                  "display_name" => {
                    "field_number" => 2,
                    "name_in_index" => "displayName"
                  }
                }
              }
            }
          })
        end

        it "preserves a field number across a public field rename" do
          results = define_proto_schema do |s|
            s.configure_proto_field_number_mappings(
              {
                "messages" => {
                  "Account" => {
                    "fields" => {
                      "full_name" => 7
                    }
                  }
                }
              }
            )

            s.object_type "Account" do |t|
              t.field "id", "ID"
              t.field "display_name", "String" do |f|
                f.renamed_from "full_name"
              end
              t.index "accounts"
            end
          end

          expect(proto_schema_from(results)).to include("string id = 1;")
          expect(proto_schema_from(results)).to include("string display_name = 7;")
          expect(results.proto_field_number_mappings).to eq({
            "messages" => {
              "Account" => {
                "fields" => {
                  "id" => 1,
                  "display_name" => 7
                }
              }
            }
          })
        end

        it "raises an error when a custom scalar does not configure proto_field" do
          results = define_proto_schema do |s|
            s.scalar_type "UnconfiguredScalar" do |t|
              t.mapping type: "keyword"
              t.json_schema type: "object"
            end

            s.object_type "Widget" do |t|
              t.field "id", "ID"
              t.field "value", "UnconfiguredScalar"
              t.index "widgets"
            end
          end

          expect {
            proto_schema_from(results)
          }.to raise_error(Errors::SchemaError, a_string_including(
            "Protobuf field type not configured for scalar type `UnconfiguredScalar`.",
            "call `proto_field type:"
          ))
        end

        it "prefixes enum values and escapes proto keywords in generated identifiers" do
          results = define_proto_schema do |s|
            s.enum_type "Command" do |t|
              t.values "option", "stream"
            end

            s.object_type "Request" do |t|
              t.field "id", "ID"
              t.field "package", "String"
              t.field "command", "Command"
              t.index "requests"
            end
          end

          expect(proto_schema_from(results)).to include("COMMAND_OPTION = 1;")
          expect(proto_schema_from(results)).to include("COMMAND_STREAM = 2;")
          expect(proto_schema_from(results)).to include("string package_ = 2; // source name: package")
        end

        it "can source enum values from configured proto enum mappings" do
          proto_status = ::Class.new do
            def self.enums
              [
                ::Data.define(:name).new(name: :UNKNOWN_DO_NOT_USE),
                ::Data.define(:name).new(name: :ACTIVE),
                ::Data.define(:name).new(name: :INACTIVE)
              ]
            end
          end

          results = define_proto_schema do |s|
            s.proto_enum_mappings(
              "Status" => {
                proto_status => {
                  exclusions: [:UNKNOWN_DO_NOT_USE],
                  expected_extras: [:LEGACY]
                }
              }
            )

            s.enum_type "Status" do |t|
              t.values "ACTIVE", "INACTIVE", "OBSOLETE"
            end

            s.object_type "Account" do |t|
              t.field "id", "ID"
              t.field "status", "Status"
              t.index "accounts"
            end
          end

          generated = proto_schema_from(results)
          expect(generated).to include("STATUS_ACTIVE = 1;")
          expect(generated).to include("STATUS_INACTIVE = 2;")
          expect(generated).to include("STATUS_LEGACY = 3;")
          expect(generated).not_to include("OBSOLETE")
        end

        it "raises when mapped proto enum sources produce inconsistent values" do
          proto_status_a = ::Class.new do
            def self.enums
              [
                ::Data.define(:name).new(name: :ACTIVE),
                ::Data.define(:name).new(name: :INACTIVE)
              ]
            end
          end

          proto_status_b = ::Class.new do
            def self.enums
              [
                ::Data.define(:name).new(name: :ACTIVE),
                ::Data.define(:name).new(name: :PENDING)
              ]
            end
          end

          results = define_proto_schema do |s|
            s.proto_enum_mappings(
              "Status" => {
                proto_status_a => {},
                proto_status_b => {}
              }
            )

            s.enum_type "Status" do |t|
              t.values "ACTIVE", "INACTIVE"
            end

            s.object_type "Account" do |t|
              t.field "id", "ID"
              t.field "status", "Status"
              t.index "accounts"
            end
          end

          expect {
            proto_schema_from(results)
          }.to raise_error(Errors::SchemaError, a_string_including(
            "Protobuf enum mappings for `Status` produce inconsistent value sets"
          ))
        end
      end
    end
  end
end
