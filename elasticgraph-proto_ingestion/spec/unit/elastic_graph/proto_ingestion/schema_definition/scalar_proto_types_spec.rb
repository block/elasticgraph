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
      # Covers how scalar types map to proto field types: the `type:`, `import:`, and `comment:`
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

        it "lets `on_built_in_types` override a built-in scalar's protobuf type, dropping its import" do
          proto = define_proto_schema do |s|
            s.on_built_in_types do |type|
              type.protobuf type: "string", comment: "ISO 8601 timestamp" if type.name == "DateTime"
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
              string created_at = 2; // ISO 8601 timestamp
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

        it "renders the format comment after the field number, below any doc comment" do
          proto = define_proto_schema do |s|
            s.object_type "Person" do |t|
              t.field "id", "ID"
              t.field "important_dates", "[Date!]!" do |f|
                f.documentation "The dates that matter to this person."
              end
              t.index "people"
            end
          end

          expect(proto_type_def_from(proto, "Person")).to eq(<<~PROTO.strip)
            message Person {
              string id = 1;
              // The dates that matter to this person.
              repeated string important_dates = 2; // ISO 8601 date, e.g. "2024-11-25"
              // Next field number: 3
            }
          PROTO
        end

        it "renders the `import:` and `comment:` configured on a custom scalar type" do
          proto = define_proto_schema do |s|
            s.scalar_type "Money" do |t|
              t.mapping type: "keyword"
              t.protobuf type: "myapp.types.Money", import: "my-app/types/v1.money.proto", comment: "amount + currency"
            end

            s.object_type "Order" do |t|
              t.field "id", "ID"
              t.field "total", "Money"
              t.index "orders"
            end
          end

          expect(proto).to include('import "my-app/types/v1.money.proto";')
          expect(proto).to include("myapp.types.Money total = 2; // amount + currency")
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

        it "rejects a multi-line `comment:`, which would emit its later lines as bare proto syntax" do
          expect {
            define_proto_schema do |s|
              s.scalar_type "Money" do |t|
                t.mapping type: "keyword"
                t.protobuf type: "myapp.types.Money", comment: "amount + currency\nin minor units"
              end
            end
          }.to raise_error(Errors::SchemaError, a_string_including("`protobuf` comment for `Money` must be a single line"))
        end
      end
    end
  end
end
