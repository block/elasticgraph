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
            ingestion_state: results.state.proto_ingestion_state,
            sourced_from_source_type_names: results.sourced_update_targets_by_source_type_name.keys.to_set,
            derived_indexing_type_names: results.derived_indexing_type_names
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

        it "applies `exclusions` to the transformed names, not the proto enum's original names" do
          proto_currency = ::Class.new do
            def self.enums
              [
                ::Data.define(:name).new(name: :CURRENCY_UNKNOWN),
                ::Data.define(:name).new(name: :CURRENCY_USD)
              ]
            end
          end

          strip_prefix = ->(name) { name.sub(/\ACURRENCY_/, "") }

          define_currency_schema = lambda do |exclusions|
            define_proto_schema do |s|
              s.enum_type "Currency" do |t|
                t.values "USD"
                t.external_proto_enum proto_currency, exclusions: exclusions, name_transform: strip_prefix
              end

              s.object_type "Account" do |t|
                t.field "id", "ID"
                t.field "currency", "Currency"
                t.index "accounts"
              end
            end
          end

          # `UNKNOWN` is the name left after the transform runs, so excluding it drops the value.
          expect(define_currency_schema.call([:UNKNOWN])).not_to include("CURRENCY_UNKNOWN")

          # The pre-transform name matches nothing, so the value survives. These two assertions
          # together pin the ordering: swapping it would flip both.
          expect(define_currency_schema.call([:CURRENCY_UNKNOWN])).to include("CURRENCY_UNKNOWN = 1;")
        end

        it "does not reserve the number of an `expected_extras` value it just emitted" do
          proto_status = ::Class.new do
            def self.enums
              [::Data.define(:name).new(name: :ACTIVE)]
            end
          end

          proto = define_proto_schema do |s|
            s.enum_type "Status" do |t|
              t.values "ACTIVE"
              t.external_proto_enum proto_status, expected_extras: [:LEGACY]
            end

            s.object_type "Account" do |t|
              t.field "id", "ID"
              t.field "status", "Status"
              t.index "accounts"
            end
          end

          # `LEGACY` has no ElasticGraph enum value, so keying the reserved set off the
          # ElasticGraph values would emit `STATUS_LEGACY = 2;` and `reserved 2;` together.
          expect(proto).to include("STATUS_LEGACY = 2;")
          expect(proto_type_def_from(proto, "Status")).not_to include("reserved")
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

          proto_status_c = ::Class.new do
            def self.enums
              [
                ::Data.define(:name).new(name: :ACTIVE),
                ::Data.define(:name).new(name: :INACTIVE)
              ]
            end
          end

          results = define_proto_schema_results do |s|
            s.enum_type "Status" do |t|
              t.values "ACTIVE", "INACTIVE"
              t.external_proto_enum proto_status_a
              t.external_proto_enum proto_status_b
              t.external_proto_enum proto_status_c
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
              expect(t.proto_name).to eq("Status")
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

          proto = define_proto_schema(proto_field_number_mappings: {
            "enums" => {"Status" => {
              "values" => {"ACTIVE" => 1, "INACTIVE" => 2},
              "next_number" => 3
            }}
          }) do |s|
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

        it "records a referenced enum's numbers so dropping `proto:`/`import:` does not renumber it" do
          proto_status = ::Class.new do
            def self.enums
              [
                ::Data.define(:name, :number).new(name: :ACTIVE, number: 7),
                ::Data.define(:name, :number).new(name: :INACTIVE, number: 9)
              ]
            end
          end

          define_account_schema = lambda do |prior_results, &configure_enum|
            define_proto_schema_results(prior_results) do |s|
              s.enum_type "Status" do |t|
                t.values "ACTIVE", "INACTIVE"
                configure_enum.call(t)
              end

              s.object_type "Account" do |t|
                t.field "id", "ID"
                t.field "status", "Status"
                t.index "accounts"
              end
            end
          end

          # Dump 1: referenced externally, so no local enum is generated -- but the external
          # numbers still land in the artifact.
          first_dump = define_account_schema.call(nil) do |t|
            t.external_proto_enum proto_status,
              proto: "myapp.types.Status",
              import: "myapp/types/status.proto"
          end

          expect(first_dump.proto_field_number_mappings.dig("enums", "Status", "values")).to eq(
            {"ACTIVE" => 7, "INACTIVE" => 9}
          )

          # Dump 2: the reference is dropped, so the enum is generated locally. Without the
          # recorded numbers it would restart from 1 and silently reinterpret existing wire data.
          second_dump = define_account_schema.call(first_dump) { |t| }

          expect(proto_type_def_from(second_dump.proto_schema, "Status")).to include(
            "STATUS_ACTIVE = 7;",
            "STATUS_INACTIVE = 9;"
          )
        end

        it "raises when a referenced enum uses number 0, which the generated zero value owns" do
          proto_status = ::Class.new do
            def self.enums
              [
                ::Data.define(:name, :number).new(name: :ACTIVE, number: 0),
                ::Data.define(:name, :number).new(name: :INACTIVE, number: 1)
              ]
            end
          end

          expect {
            define_proto_schema do |s|
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
          }.to raise_error(Errors::SchemaError, a_string_including("assigns `ACTIVE` the number 0"))
        end

        it "raises when a referenced enum uses a number outside the valid protobuf range" do
          proto_status = ::Class.new do
            def self.enums
              [
                ::Data.define(:name, :number).new(name: :ACTIVE, number: 1),
                ::Data.define(:name, :number).new(name: :INACTIVE, number: 2_147_483_648)
              ]
            end
          end

          expect {
            define_proto_schema do |s|
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
          }.to raise_error(Errors::SchemaError, a_string_including(
            "assigns `INACTIVE` the number 2147483648, which is not a valid protobuf enum value number"
          ))
        end
      end
    end
  end
end
