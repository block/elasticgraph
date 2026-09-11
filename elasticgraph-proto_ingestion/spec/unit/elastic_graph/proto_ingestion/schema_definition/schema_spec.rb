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
            ingestion_state: results.state.proto_ingestion_state
          )

          first_generation = generator.to_proto

          second_generation = generator.to_proto
          expect(second_generation).to eq(first_generation)
          expect(second_generation).not_to be(first_generation)
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
