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
            s.enum_type "Status" do |t|
              t.documentation "The status of an account.\n\nUsed when ingesting accounts."
              t.value "ACTIVE" do |v|
                v.documentation "The account is active."
              end
              t.value "INACTIVE"
            end

            s.object_type "Address" do |t|
              t.field "street", "String"
              t.field "city", "String"
            end

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
          end

          expect(proto).to eq(<<~PROTO)
            syntax = "proto3";

            package elasticgraph;

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

            // An account in the system.
            message Account {
              // The account's unique identifier.
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
            "optional Status status = 2;",
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
                Car car = 1;
                Bike bike = 2;
              }
            }
          PROTO
          expect(proto_type_def_from(proto, "Inventor")).to eq(<<~PROTO.strip)
            message Inventor {
              oneof value {
                Person person = 1;
                Company company = 2;
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

        it "flattens nested interfaces and snake-cases multiword oneof alternatives" do
          proto = define_proto_schema do |s|
            s.object_type "DeliveryVehicle" do |t|
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
                DeliveryVehicle delivery_vehicle = 1;
              }
            }
          PROTO
          expect(proto_type_def_from(proto, "DeliveryVehicle")).to include("string id = 1;")
          expect(proto_type_def_from(proto, "MotorVehicle")).to be_nil
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

        it "combines source name and format comments on a single field" do
          proto = define_proto_schema do |s|
            s.object_type "Person" do |t|
              t.field "id", "ID"
              t.field "option", "Date"
              t.index "people"
            end
          end

          expect(proto).to include(
            %(string option_ = 2; // source name: option; ISO 8601 date, e.g. "2024-11-25")
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

        it "can assign field numbers from configured mappings" do
          results = define_proto_schema_results do |s|
            s.configure_proto_field_number_mappings(
              {
                "messages" => {
                  "Account" => {
                    "id" => 10,
                    "name" => 2
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

          generated = results.proto_schema
          expect(generated).to include("string id = 10;")
          expect(generated).to include("string name = 2;")
        end

        it "assigns new field numbers after mapped values when mappings are partial" do
          results = define_proto_schema_results do |s|
            s.configure_proto_field_number_mappings(
              {
                "messages" => {
                  "Account" => {
                    "id" => 1
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

          expect(results.proto_schema).to include("string name = 2;")
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
                }
              }
            }
          })
        end

        it "exposes field and enum number mappings in canonical order" do
          results = define_proto_schema_results do |s|
            s.configure_proto_field_number_mappings(
              {
                "messages" => {
                  "ZMessage" => {"fields" => {"second" => 2, "first" => 1}},
                  "AMessage" => {"fields" => {"only" => 3}}
                },
                "enums" => {
                  "ZEnum" => {"values" => {"SECOND" => 2, "FIRST" => 1}},
                  "AEnum" => {"values" => {"ONLY" => 3}}
                }
              }
            )
          end

          mappings = results.proto_field_number_mappings
          expect(mappings.fetch("messages").keys).to eq(["AMessage", "ZMessage"])
          expect(mappings.dig("messages", "ZMessage", "fields").keys).to eq(["first", "second"])
          expect(mappings.fetch("enums").keys).to eq(["AEnum", "ZEnum"])
          expect(mappings.dig("enums", "ZEnum", "values").keys).to eq(["FIRST", "SECOND"])
        end

        it "preserves reserved numbers for removed fields and allocates new numbers above them" do
          results = define_proto_schema_results do |s|
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

          generated = results.proto_schema
          expect(generated).to include("string id = 1;")
          expect(generated).to include("string name = 3;")

          expect(results.proto_field_number_mappings).to eq({
            "enums" => {},
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
          results = define_proto_schema_results do |s|
            s.object_type "Widget" do |t|
              t.field "id", "ID"
              t.field "display_name", "String", name_in_index: "displayName"
              t.index "widgets"
            end
          end

          expect(results.proto_schema).to include("string display_name = 2;")
          expect(results.proto_schema).not_to include("displayName")

          expect(results.proto_field_number_mappings).to eq({
            "enums" => {},
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
          results = define_proto_schema_results do |s|
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

          expect(results.proto_schema).to include("string id = 1;")
          expect(results.proto_schema).to include("string display_name = 7;")
          expect(results.proto_field_number_mappings).to eq({
            "enums" => {},
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

        it "generates the proto schema and assigns field numbers when no renames are declared" do
          results = define_proto_schema_results do |s|
            s.object_type "Account" do |t|
              t.field "id", "ID"
              t.field "display_name", "String"
              t.index "accounts"
            end
          end

          expect(results.proto_schema).to eq(<<~PROTO)
            syntax = "proto3";

            package elasticgraph;

            message Account {
              string id = 1;
              string display_name = 2;
            }
          PROTO

          expect(results.proto_field_number_mappings).to eq({
            "enums" => {},
            "messages" => {
              "Account" => {
                "fields" => {
                  "id" => 1,
                  "display_name" => 2
                }
              }
            }
          })
        end

        it "preserves enum value numbers from configured mappings, reserving removed values' numbers" do
          results = define_proto_schema_results do |s|
            s.configure_proto_field_number_mappings(
              {
                "enums" => {
                  "Status" => {
                    "values" => {
                      "ACTIVE" => 1,
                      "PAUSED" => 2,
                      "INACTIVE" => 3
                    }
                  }
                }
              }
            )

            # `PAUSED` has been removed since the mappings were dumped, and `ARCHIVED` has been added.
            s.enum_type "Status" do |t|
              t.values "ACTIVE", "INACTIVE", "ARCHIVED"
            end

            s.object_type "Account" do |t|
              t.field "id", "ID"
              t.field "status", "Status"
              t.index "accounts"
            end
          end

          expect(proto_type_def_from(results.proto_schema, "Status")).to include(
            "STATUS_ACTIVE = 1;",
            "STATUS_INACTIVE = 3;",
            "STATUS_ARCHIVED = 4;"
          )

          # `PAUSED` keeps its number reserved in the artifact so it is never reused for a new value.
          expect(results.proto_field_number_mappings.fetch("enums")).to eq({
            "Status" => {
              "values" => {
                "ACTIVE" => 1,
                "PAUSED" => 2,
                "INACTIVE" => 3,
                "ARCHIVED" => 4
              }
            }
          })
        end

        it "raises a clear error when the configured mappings assign the same number to two enum values" do
          results = define_proto_schema_results do |s|
            s.configure_proto_field_number_mappings(
              {"enums" => {"Status" => {"values" => {"ACTIVE" => 1, "INACTIVE" => 1}}}}
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
            results.proto_schema
          }.to raise_error(Errors::SchemaError, a_string_including(
            "enum value-number mapping collision in enum `Status`",
            "`ACTIVE` and `INACTIVE`",
            "number 1"
          ))
        end

        it "rejects field numbers that are not integers rather than silently truncating them" do
          results = define_proto_schema_results do |s|
            s.configure_proto_field_number_mappings(
              {"messages" => {"Account" => {"fields" => {"id" => 1.5}}}}
            )

            s.object_type "Account" do |t|
              t.field "id", "ID"
              t.index "accounts"
            end
          end

          expect {
            results.proto_schema
          }.to raise_error(Errors::SchemaError, a_string_including("`Account.id`", "must be an integer", "1.5"))
        end

        it "preserves stable field numbers for oneof alternatives" do
          results = define_proto_schema_results do |s|
            s.configure_proto_field_number_mappings(
              {
                "messages" => {
                  "Vehicle" => {
                    "fields" => {
                      "removed" => 1,
                      "car" => 4,
                      "bike" => 8
                    }
                  }
                }
              }
            )

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

          vehicle = proto_type_def_from(results.proto_schema, "Vehicle")
          expect(vehicle).to include("Car car = 4;", "Bike bike = 8;", "Scooter scooter = 2;")
          expect(results.proto_field_number_mappings.fetch("messages").fetch("Vehicle")).to eq({
            "fields" => {
              "removed" => 1,
              "scooter" => 2,
              "car" => 4,
              "bike" => 8
            }
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
              t.field "count", "BigNumber"
              t.index "accounts"
            end
          end

          expect(proto_type_def_from(proto, "Account")).to include("int64 count = 2;")
        end

        it "prefixes enum values and escapes proto keywords in generated identifiers" do
          proto = define_proto_schema do |s|
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

          expect(proto_type_def_from(proto, "Command")).to include("COMMAND_OPTION = 1;", "COMMAND_STREAM = 2;")
          expect(proto_type_def_from(proto, "Request")).to include("string package_ = 2; // source name: package")
        end

        it "sources enum values from an external proto enum" do
          proto_status = ::Class.new do
            def self.enums
              [
                ::Data.define(:name).new(name: :UNKNOWN_DO_NOT_USE),
                ::Data.define(:name).new(name: :ACTIVE),
                ::Data.define(:name).new(name: :INACTIVE)
              ]
            end
          end

          proto = define_proto_schema do |s|
            s.enum_type "Status" do |t|
              t.values "ACTIVE", "INACTIVE", "OBSOLETE"
              t.external_proto_enum proto_status,
                exclusions: [:UNKNOWN_DO_NOT_USE],
                expected_extras: [:LEGACY]
            end

            s.object_type "Account" do |t|
              t.field "id", "ID"
              t.field "status", "Status"
              t.index "accounts"
            end
          end

          generated = proto
          expect(generated).to include("STATUS_ACTIVE = 1;")
          expect(generated).to include("STATUS_INACTIVE = 2;")
          expect(generated).to include("STATUS_LEGACY = 3;")
          expect(generated).not_to include("OBSOLETE")
        end

        it "applies `name_transform` to external proto enum value names" do
          proto_currency = ::Class.new do
            def self.enums
              [
                ::Data.define(:name).new(name: :CURRENCY_USD),
                ::Data.define(:name).new(name: :CURRENCY_CAD)
              ]
            end
          end

          proto = define_proto_schema do |s|
            s.enum_type "Currency" do |t|
              t.values "USD", "CAD"
              t.external_proto_enum proto_currency, name_transform: ->(name) { name.sub(/\ACURRENCY_/, "") }
            end

            s.object_type "Account" do |t|
              t.field "id", "ID"
              t.field "currency", "Currency"
              t.index "accounts"
            end
          end

          generated = proto
          expect(generated).to include("CURRENCY_USD = 1;")
          expect(generated).to include("CURRENCY_CAD = 2;")
          expect(generated).not_to include("CURRENCY_CURRENCY_")
        end

        it "raises when external proto enum sources produce inconsistent values" do
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

          results = define_proto_schema_results do |s|
            s.enum_type "Status" do |t|
              t.values "ACTIVE", "INACTIVE"
              t.external_proto_enum proto_status_a
              t.external_proto_enum proto_status_b
            end

            s.object_type "Account" do |t|
              t.field "id", "ID"
              t.field "status", "Status"
              t.index "accounts"
            end
          end

          expect {
            results.proto_schema
          }.to raise_error(Errors::SchemaError, a_string_including(
            "External proto enums for `Status` produce inconsistent value sets"
          ))
        end

        it "references an external proto enum type instead of generating a local enum" do
          proto_status = ::Class.new do
            def self.enums
              [
                ::Data.define(:name, :number).new(name: :ACTIVE, number: 1),
                ::Data.define(:name, :number).new(name: :INACTIVE, number: 2)
              ]
            end
          end

          proto = define_proto_schema do |s|
            s.enum_type "Status" do |t|
              t.values "ACTIVE", "INACTIVE"
              t.external_proto_enum proto_status,
                proto: "myapp.types.Status",
                import: "myapp/types/status.proto"
            end

            s.object_type "Account" do |t|
              t.field "id", "ID"
              t.field "status", "Status"
              t.field "previous_status", "Status"
              t.index "accounts"
            end
          end

          generated = proto
          expect(generated.scan('import "myapp/types/status.proto";').size).to eq(1)
          expect(generated).to include("myapp.types.Status status = 2;")
          expect(generated).to include("myapp.types.Status previous_status = 3;")
          expect(generated).not_to include("enum Status")
        end

        it "accepts a referenced enum whose numbers match previously pinned enum value numbers" do
          proto_status = ::Class.new do
            def self.enums
              [
                ::Data.define(:name, :number).new(name: :ACTIVE, number: 1),
                ::Data.define(:name, :number).new(name: :INACTIVE, number: 2)
              ]
            end
          end

          proto = define_proto_schema do |s|
            s.configure_proto_field_number_mappings(
              {"enums" => {"Status" => {"values" => {"ACTIVE" => 1, "INACTIVE" => 2}}}}
            )

            s.enum_type "Status" do |t|
              t.values "ACTIVE", "INACTIVE"
              t.external_proto_enum proto_status,
                proto: "myapp.types.Status",
                import: "myapp/types/status.proto"
            end

            s.object_type "Account" do |t|
              t.field "id", "ID"
              t.field "status", "Status"
              t.index "accounts"
            end
          end

          expect(proto).to include("myapp.types.Status status = 2;")
        end
      end
    end
  end
end
