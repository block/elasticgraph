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
        it "returns an empty string when no indexed types are present" do
          proto = define_proto_schema do |s|
            s.object_type "Point" do |t|
              t.field "x", "Float"
              t.field "y", "Float"
            end
          end

          expect(proto).to eq("")
        end

        it "raises when enum values map to duplicate proto value names" do
          expect {
            define_proto_schema do |s|
              s.enum_type "Status" do |t|
                t.values "option", "OPTION"
              end
            end
          }.to raise_error(Errors::SchemaError, a_string_including(
            "Enum `Status` values `option` and `OPTION`",
            "duplicate proto enum value name `STATUS_OPTION`"
          ))
        end

        it "raises when externally sourced enum values map to duplicate proto value names" do
          proto_status = SchemaSupport::ProtoEnum.new(enums: [
            SchemaSupport::ProtoEnumEntryNameOnly.new(name: :option),
            SchemaSupport::ProtoEnumEntryNameOnly.new(name: :OPTION)
          ])

          results = define_proto_schema_results do |s|
            s.enum_type "Status" do |t|
              t.value "ACTIVE"
              t.external_proto_enum proto_status
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
            "Enum `Status` maps to duplicate proto enum value names: STATUS_OPTION"
          ))
        end

        it "raises when an externally sourced enum value conflicts with the generated zero value" do
          proto_status = SchemaSupport::ProtoEnum.new(enums: [SchemaSupport::ProtoEnumEntryNameOnly.new(name: :UNSPECIFIED)])

          results = define_proto_schema_results do |s|
            s.enum_type "Status" do |t|
              t.value "ACTIVE"
              t.external_proto_enum proto_status
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
            "Enum `Status` value `UNSPECIFIED`",
            "conflicts with the generated zero value `STATUS_UNSPECIFIED`"
          ))
        end

        it "raises when an enum value conflicts with the generated zero value" do
          expect {
            define_proto_schema do |s|
              s.enum_type "Status" do |t|
                t.values "ACTIVE", "UNSPECIFIED"
              end
            end
          }.to raise_error(Errors::SchemaError, a_string_including(
            "Enum `Status` value `UNSPECIFIED`",
            "conflicts with the generated zero value `STATUS_UNSPECIFIED`"
          ))
        end

        it "raises when emitted enums map to the same protobuf enum value prefix" do
          expect {
            define_proto_schema do |s|
              s.enum_type "HttpStatus" do |t|
                t.value "AVAILABLE"
              end

              s.enum_type "HTTPStatus" do |t|
                t.value "UNAVAILABLE"
              end

              s.object_type "Endpoint" do |t|
                t.field "id", "ID"
                t.field "externalStatus", "HttpStatus"
                t.field "internalStatus", "HTTPStatus"
                t.index "endpoints"
              end
            end
          }.to raise_error(Errors::SchemaError, a_string_including(
            "Enum types `HttpStatus` and `HTTPStatus`",
            "duplicate protobuf enum value prefix `HTTP_STATUS`"
          ))
        end

        it "allows colliding enum value prefixes when only one enum is emitted" do
          proto = define_proto_schema do |s|
            s.enum_type "HttpStatus" do |t|
              t.value "AVAILABLE"
            end

            s.enum_type "HTTPStatus" do |t|
              t.value "UNAVAILABLE"
            end

            s.object_type "Endpoint" do |t|
              t.field "id", "ID"
              t.field "status", "HttpStatus"
              t.index "endpoints"
            end
          end

          expect(proto).to include("enum HttpStatus {")
          expect(proto).not_to include("enum HTTPStatus {")
        end

        it "fully qualifies local type references so they do not conflict with contextual protobuf keywords" do
          proto = define_proto_schema do |s|
            s.enum_type "option" do |t|
              t.value "ACTIVE"
            end

            s.object_type "string" do |t|
              t.field "id", "ID"
            end

            s.object_type "Event" do |t|
              t.field "id", "ID"
              t.field "option", "option"
              t.field "message", "string"
              t.index "events"
            end
          end

          expect(proto_type_def_from(proto, "option")).to start_with("enum option {")
          expect(proto_type_def_from(proto, "string")).to start_with("message string {")
          expect(proto_type_def_from(proto, "Event")).to include(
            ".elasticgraph.option option = 2;",
            ".elasticgraph.string message = 3;"
          )
        end

        it "raises when proto fields are accessed before the schema definition is complete" do
          expect {
            define_proto_schema do |s|
              s.object_type "Account" do |t|
                t.field "id", "ID"
                t.send(:proto_fields)
              end
            end
          }.to raise_error(Errors::SchemaError, "Cannot access `proto_fields` until the schema definition is complete.")
        end

        it "renders a shared enum only once when multiple indexed types reference it" do
          proto = define_proto_schema do |s|
            s.enum_type "Status" do |t|
              t.value "ACTIVE"
            end

            s.object_type "Account" do |t|
              t.field "id", "ID"
              t.field "status", "Status"
              t.index "accounts"
            end

            s.object_type "User" do |t|
              t.field "id", "ID"
              t.field "status", "Status"
              t.index "users"
            end
          end

          expect(proto.scan("enum Status ").size).to eq(1)
          expect(proto_type_def_from(proto, "Account")).to include(".elasticgraph.Status status = 2;")
          expect(proto_type_def_from(proto, "User")).to include(".elasticgraph.Status status = 2;")
        end

        it "raises when `external_proto_enum` is given an object without `.enums`" do
          expect {
            define_proto_schema do |s|
              s.enum_type "Status" do |t|
                t.values "ACTIVE"
                t.external_proto_enum ::Object.new
              end
            end
          }.to raise_error(Errors::SchemaError, a_string_including(
            "`external_proto_enum` on `Status`", "must be given a proto enum class with `.enums`"
          ))
        end

        it "wraps unexpected exceptions from external proto enum sources" do
          proto_status = SchemaSupport::ProtoEnum.new(enums: [SchemaSupport::ProtoEnumEntryNameOnly.new(name: :ACTIVE)])

          results = define_proto_schema_results do |s|
            s.enum_type "Status" do |t|
              t.values "ACTIVE"
              t.external_proto_enum proto_status, name_transform: ->(_name) { raise "boom" }
            end

            s.object_type "Account" do |t|
              t.field "id", "ID"
              t.field "status", "Status"
              t.index "accounts"
            end
          end

          expect {
            results.proto_schema
          }.to raise_error(Errors::SchemaError, a_string_including("Failed loading external proto enum values for `Status`"))
        end

        it "accepts multiple external proto enum sources when they resolve to the same values" do
          proto_status_a = SchemaSupport::ProtoEnum.new(enums: [SchemaSupport::ProtoEnumEntryNameOnly.new(name: :ACTIVE)])

          proto_status_b = SchemaSupport::ProtoEnum.new(enums: [SchemaSupport::ProtoEnumEntryNameOnly.new(name: :ACTIVE)])

          results = define_proto_schema_results do |s|
            s.enum_type "Status" do |t|
              t.values "ACTIVE"
              t.external_proto_enum proto_status_a
              t.external_proto_enum proto_status_b
            end

            s.object_type "Account" do |t|
              t.field "id", "ID"
              t.field "status", "Status"
              t.index "accounts"
            end
          end

          expect(results.proto_schema).to include("STATUS_ACTIVE = 1;")
        end

        it "requires both `proto` and `import` as non-empty Strings to reference an external proto enum type" do
          # The eager validation raises before `.enums` is ever consulted.
          proto_status = SchemaSupport::ProtoEnum.new(enums: [])

          [
            {proto: "myapp.types.Status"},
            {import: "myapp/types/status.proto"},
            {proto: "", import: "myapp/types/status.proto"},
            {proto: :"myapp.types.Status", import: "myapp/types/status.proto"}
          ].each do |reference_options|
            expect {
              define_proto_schema do |s|
                s.enum_type "Status" do |t|
                  t.values "ACTIVE"
                  t.external_proto_enum proto_status, **reference_options
                end
              end
            }.to raise_error(Errors::SchemaError, a_string_including(
              "`external_proto_enum` on `Status`", "must be given both `proto` and `import` as non-empty Strings"
            ))
          end
        end

        it "raises when an external reference is combined with transform options" do
          # The eager validation raises before `.enums` is ever consulted.
          proto_status = SchemaSupport::ProtoEnum.new(enums: [])

          expect {
            define_proto_schema do |s|
              s.enum_type "Status" do |t|
                t.values "ACTIVE"
                t.external_proto_enum proto_status,
                  exclusions: [:LEGACY],
                  proto: "myapp.types.Status",
                  import: "myapp/types/status.proto"
              end
            end
          }.to raise_error(Errors::SchemaError, a_string_including(
            "cannot combine `proto`/`import` with `exclusions`, `expected_extras`, or `name_transform`",
            "must stay generated locally"
          ))
        end

        it "raises when a referenced enum has multiple sources" do
          # The multi-source validation raises before `.enums` is ever consulted.
          proto_status_a = SchemaSupport::ProtoEnum.new(enums: [])
          proto_status_b = SchemaSupport::ProtoEnum.new(enums: [])

          results = define_proto_schema_results do |s|
            s.enum_type "Status" do |t|
              t.values "ACTIVE"
              t.external_proto_enum proto_status_a,
                proto: "myapp.types.Status",
                import: "myapp/types/status.proto"
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
            "must use exactly one `external_proto_enum` source",
            "cannot be safely referenced externally"
          ))
        end

        it "raises when a referenced enum's external values do not match the ElasticGraph enum values" do
          proto_status = SchemaSupport::ProtoEnum.new(enums: [
            SchemaSupport::ProtoEnumEntry.new(name: :ACTIVE, number: 1),
            SchemaSupport::ProtoEnumEntry.new(name: :PENDING, number: 2)
          ])

          results = define_proto_schema_results do |s|
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

          expect {
            results.proto_schema
          }.to raise_error(Errors::SchemaError, a_string_including(
            "External proto enum `Status` values do not match the ElasticGraph enum values",
            "External values: ACTIVE, PENDING",
            "ElasticGraph values: ACTIVE, INACTIVE"
          ))
        end

        it "raises when a referenced enum's entries do not expose value numbers" do
          proto_status = SchemaSupport::ProtoEnum.new(enums: [SchemaSupport::ProtoEnumEntryNameOnly.new(name: :ACTIVE)])

          results = define_referenced_status_schema(proto_status, values: ["ACTIVE"])

          expect {
            results.proto_schema
          }.to raise_error(Errors::SchemaError, a_string_including(
            "must expose `.number` so its values can be verified against previously pinned numbers"
          ))
        end

        it "raises when a referenced enum changes a pinned value's number" do
          proto_status = SchemaSupport::ProtoEnum.new(enums: [
            SchemaSupport::ProtoEnumEntry.new(name: :ACTIVE, number: 2),
            SchemaSupport::ProtoEnumEntry.new(name: :INACTIVE, number: 1)
          ])

          results = define_referenced_status_schema(
            proto_status,
            values: ["ACTIVE", "INACTIVE"],
            pinned_value_numbers: {"ACTIVE" => 1, "INACTIVE" => 2}
          )

          expect {
            results.proto_schema
          }.to raise_error(Errors::SchemaError, a_string_including(
            "assigns `ACTIVE` the number 2, but previously dumped artifacts pin it to 1",
            "silently reinterpret existing wire data"
          ))
        end

        it "raises when a referenced enum reuses a pinned number for a different value" do
          proto_status = SchemaSupport::ProtoEnum.new(enums: [
            SchemaSupport::ProtoEnumEntry.new(name: :ACTIVE, number: 1),
            SchemaSupport::ProtoEnumEntry.new(name: :LEGACY, number: 2)
          ])

          # `PAUSED` was removed from the enum; its number stays reserved in the artifact.
          results = define_referenced_status_schema(
            proto_status,
            values: ["ACTIVE", "LEGACY"],
            pinned_value_numbers: {"ACTIVE" => 1, "PAUSED" => 2}
          )

          expect {
            results.proto_schema
          }.to raise_error(Errors::SchemaError, a_string_including(
            "assigns `LEGACY` the number 2, which previously dumped artifacts pin to `PAUSED`",
            "silently reinterpret existing wire data"
          ))
        end

        it "wraps unexpected exceptions from referenced proto enum sources" do
          proto_status = ::Class.new do
            def self.enums
              raise "boom"
            end
          end

          results = define_referenced_status_schema(proto_status, values: ["ACTIVE"])

          expect {
            results.proto_schema
          }.to raise_error(Errors::SchemaError, a_string_including("Failed loading external proto enum values for `Status`"))
        end

        it "raises when a hand-edited mappings artifact is invalid" do
          # An invalid artifact can only arise from hand-editing (a prior dump is always valid),
          # so this test must seed raw mappings instead of results from a prior dump.
          results = define_proto_schema_results(proto_field_number_mappings: {
            "messages" => {"Account" => {"fields" => {"id" => 0}}}
          }) do |s|
            s.object_type "Account" do |t|
              t.field "id", "ID"
              t.index "accounts"
            end
          end

          expect {
            results.proto_schema
          }.to raise_error(Errors::SchemaError, a_string_including(
            "Invalid protobuf field-number mappings", "/messages/Account/fields/id", "less than: 1"
          ))
        end

        it "skips the protobuf-reserved range when allocating new field numbers" do
          # Reaching the real reserved range (19000-19999) would require ~19,000 fields, so we
          # stub it to a small range to verify the allocator respects the constant.
          stub_const("ElasticGraph::ProtoIngestion::SchemaDefinition::FieldNumberMappings::RESERVED_FIELD_NUMBER_RANGE", 3..4)

          results = define_proto_schema_results do |s|
            s.object_type "Account" do |t|
              t.field "id", "ID"
              t.field "name", "String"
              t.field "email", "String"
              t.index "accounts"
            end
          end

          expect(results.proto_schema).to include("string id = 1;", "string name = 2;", "string email = 5;")
          expect(results.proto_field_number_mappings.dig("messages", "Account", "next_number")).to eq(6)
        end

        it "allocates the next available field number when a renamed field has no old mapping entry" do
          results1 = define_proto_schema_results do |s|
            s.object_type "Account" do |t|
              t.field "id", "ID"
              t.index "accounts"
            end
          end

          # `display_name` declares a rename from `full_name`, but no `full_name` mapping was ever dumped.
          results2 = define_proto_schema_results(results1) do |s|
            s.object_type "Account" do |t|
              t.field "id", "ID"
              t.field "display_name", "String" do |f|
                f.renamed_from "full_name"
              end
              t.index "accounts"
            end
          end

          expect(results2.proto_schema).to include("string id = 1;", "string display_name = 2;")
        end

        private

        def define_referenced_status_schema(proto_status, values:, pinned_value_numbers: nil)
          proto_field_number_mappings =
            if pinned_value_numbers
              {"enums" => {"Status" => {
                "values" => pinned_value_numbers,
                "next_number" => pinned_value_numbers.values.max + 1
              }}}
            end

          define_proto_schema_results(proto_field_number_mappings: proto_field_number_mappings) do |s|
            s.enum_type "Status" do |t|
              t.values(*values)
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
        end
      end
    end
  end
end
