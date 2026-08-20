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
      # Covers `external_proto_enum`: sourcing an ElasticGraph enum's values from a compiled proto
      # enum, and referencing an externally defined proto enum type instead of generating one.
      RSpec.describe Schema, "external proto enums" do
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
