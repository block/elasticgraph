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
      # Covers how scalar types map to proto field types: the `type:`, `import:`, and `field_comment:`
      # options of `protobuf`, and the imports and field comments they produce.
      RSpec.describe Schema, "scalar proto types" do
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

        it "lets `on_built_in_types` replace a built-in scalar's protobuf type, import, and field comment" do
          proto = define_proto_schema do |s|
            s.on_built_in_types do |type|
              # `protobuf` replaces the full configuration, so omitting `import:` here drops the
              # built-in `google/protobuf/timestamp.proto` import.
              type.protobuf type: "string", field_comment: "Must be formatted as an ISO 8601 timestamp." if type.name == "DateTime"
            end

            s.object_type "Event" do |t|
              t.field "id", "ID"
              t.field "created_at", "DateTime"
              t.index "events"
            end
          end

          expect(proto).to eq(<<~PROTO)
            syntax = "proto3";

            package elasticgraph;

            message Event {
              string id = 1;
              // Must be formatted as an ISO 8601 timestamp.
              string created_at = 2;
              // Next field number: 3
            }
          PROTO
        end

        it "drops a built-in scalar's field comment when an override omits `field_comment:`" do
          proto = define_proto_schema do |s|
            s.on_built_in_types do |type|
              # `Date` has a built-in `field_comment:` and no `import:`; this override inverts both.
              type.protobuf type: "google.type.Date", import: "google/type/date.proto" if type.name == "Date"
            end

            s.object_type "Event" do |t|
              t.field "id", "ID"
              t.field "occurred_on", "Date"
              t.index "events"
            end
          end

          expect(proto).to eq(<<~PROTO)
            syntax = "proto3";

            package elasticgraph;

            import "google/type/date.proto";

            message Event {
              string id = 1;
              google.type.Date occurred_on = 2;
              // Next field number: 3
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

        it "imports only the proto files of scalar types the generated messages reference" do
          proto = define_proto_schema do |s|
            s.scalar_type "UsedType" do |t|
              t.mapping type: "keyword"
              t.protobuf type: "example.UsedType", import: "used.proto"
            end

            s.scalar_type "UnusedType" do |t|
              t.mapping type: "keyword"
              t.protobuf type: "example.UnusedType", import: "unused.proto"
            end

            s.scalar_type "GraphQLOnlyFieldType" do |t|
              t.mapping type: "keyword"
              t.protobuf type: "example.GraphQLOnlyFieldType", import: "graphql_only_field.proto"
            end

            s.object_type "Event" do |t|
              t.field "id", "ID"
              t.field "used", "UsedType"
              t.field "graphql_only", "GraphQLOnlyFieldType", graphql_only: true
              t.index "events"
            end
          end

          expect(proto.lines.grep(/\Aimport /).map(&:chomp)).to eq([%(import "used.proto";)])
        end

        it "renders the field comment above the field, after any doc comment" do
          proto = define_proto_schema do |s|
            s.object_type "Person" do |t|
              t.field "id", "ID"
              t.field "important_dates", "[Date!]!" do |f|
                f.documentation "The dates that matter to this person."
              end
              t.field "time_zone", "TimeZone"
              t.index "people"
            end
          end

          expect(proto_type_def_from(proto, "Person")).to eq(<<~PROTO.strip)
            message Person {
              string id = 1;
              // The dates that matter to this person.
              //
              // Must be formatted as an ISO 8601 date, e.g. "2024-11-25".
              repeated string important_dates = 2;
              // Must be an IANA time zone identifier, e.g. "America/Los_Angeles".
              string time_zone = 3;
              // Next field number: 4
            }
          PROTO
        end

        it "renders the `import:` and `field_comment:` configured on a custom scalar type" do
          proto = define_proto_schema do |s|
            s.scalar_type "Money" do |t|
              t.mapping type: "keyword"
              t.protobuf type: "myapp.types.Money", import: "my-app/types/v1.money.proto", field_comment: "Amount and currency."
            end

            s.object_type "Order" do |t|
              t.field "id", "ID"
              t.field "total", "Money"
              t.index "orders"
            end
          end

          expect(proto).to include('import "my-app/types/v1.money.proto";')
          expect(proto).to include("  // Amount and currency.\n  myapp.types.Money total = 2;")
        end

        it "rejects an `import:` that is not the path of a `.proto` file" do
          invalid_imports = [
            "", # empty
            "myapp/types/money", # no `.proto` extension
            "myapp/types/money.protobuf", # extension is not exactly `.proto`
            %(myapp/types/money.proto"; import "evil.proto), # closes the rendered `import "...";`
            %(myapp/types/money.proto\nimport "evil.proto") # adds a line to the rendered proto
          ]

          # `protobuf` raises as soon as it is called, so no indexed type is needed here.
          aggregate_failures do
            invalid_imports.each do |import|
              expect {
                define_proto_schema do |s|
                  s.scalar_type "Money" do |t|
                    t.mapping type: "keyword"
                    t.protobuf type: "myapp.types.Money", import: import
                  end
                end
              }.to raise_error(Errors::SchemaError, a_string_including(
                "`protobuf` import for `Money` must be the path of a `.proto` file"
              ))
            end
          end
        end

        it "renders a multi-line `field_comment:` as multiple comment lines" do
          proto = define_proto_schema do |s|
            s.scalar_type "Money" do |t|
              t.mapping type: "keyword"
              t.protobuf type: "string", field_comment: "Must be an amount and a currency.\n\nThe amount is in minor units."
            end

            s.object_type "Order" do |t|
              t.field "id", "ID"
              t.field "total", "Money" do |f|
                f.documentation "What the customer owes."
              end
              t.index "orders"
            end
          end

          expect(proto_type_def_from(proto, "Order")).to eq(<<~PROTO.strip)
            message Order {
              string id = 1;
              // What the customer owes.
              //
              // Must be an amount and a currency.
              //
              // The amount is in minor units.
              string total = 2;
              // Next field number: 3
            }
          PROTO
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
      end
    end
  end
end
