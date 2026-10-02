# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/proto_ingestion/schema_definition/field_number_mappings"
require "elastic_graph/support/json_schema/meta_schema_validator"

module ElasticGraph
  module ProtoIngestion
    module SchemaDefinition
      RSpec.describe FieldNumberMappings do
        describe ".from_parsed_yaml" do
          it "returns empty mappings for `nil`, as parsing an empty artifact file yields" do
            mappings = FieldNumberMappings.from_parsed_yaml(nil)

            expect(mappings.to_dumpable_hash).to eq({"enums" => {}, "messages" => {}})
          end

          describe "artifact structure validation" do
            it "validates mappings against a valid JSON schema" do
              expect(Support::JSONSchema.strict_meta_schema_validator.valid?(FieldNumberMappings::JSON_SCHEMA)).to be(true)

              expect {
                FieldNumberMappings.from_parsed_yaml({
                  "enums" => {"Status" => {"values" => {"ACTIVE" => 1}}}
                })
              }.to raise_error(Errors::SchemaError, a_string_including(
                "Invalid protobuf field-number mappings", "Validation errors"
              ))
            end
          end

          it "requires complete field contracts and rejects the number-only format" do
            invalid_contracts = [
              1,
              proto_field_contract(1).except("proto_type"),
              proto_field_contract(1).except("list_depth"),
              proto_field_contract(1, ""),
              proto_field_contract(1, list_depth: -1),
              proto_field_contract(1, list_depth: 1.5),
              proto_field_contract(0),
              proto_field_contract(19_000),
              proto_field_contract(1).merge("unknown" => true)
            ]
            invalid_contracts.each do |contract|
              expect {
                FieldNumberMappings.from_parsed_yaml({
                  "messages" => {"Account" => {"fields" => {"id" => contract}, "next_number" => 2}}
                })
              }.to raise_error(Errors::SchemaError, /Invalid protobuf field-number mappings/)
            end
          end

          describe "mapping consistency validation" do
            it "raises clear errors when fields or enum values collide" do
              expect {
                FieldNumberMappings.from_parsed_yaml({
                  "messages" => {"Account" => {"fields" => {"id" => proto_field_contract(1), "name" => proto_field_contract(1)}, "next_number" => 2}}
                })
              }.to raise_error(Errors::SchemaError, a_string_including(
                "field-number mapping collision in message `Account`", "`id` and `name`", "number 1"
              ))

              expect {
                FieldNumberMappings.from_parsed_yaml({
                  "enums" => {"Status" => {"values" => {"ACTIVE" => 1, "INACTIVE" => 1}, "next_number" => 2}}
                })
              }.to raise_error(Errors::SchemaError, a_string_including(
                "enum value-number mapping collision in enum `Status`", "`ACTIVE` and `INACTIVE`", "number 1"
              ))
            end

            it "validates that each `next_number` is greater than every mapped number" do
              expect {
                FieldNumberMappings.from_parsed_yaml({
                  "messages" => {"Account" => {"fields" => {"id" => proto_field_contract(7)}, "next_number" => 7}}
                })
              }.to raise_error(Errors::SchemaError, a_string_including(
                "`next_number` for message `Account`", "greater than every mapped number", "maximum: 7", "got: 7"
              ))

              expect {
                FieldNumberMappings.from_parsed_yaml({
                  "enums" => {"Status" => {"values" => {"ACTIVE" => 7}, "next_number" => 7}}
                })
              }.to raise_error(Errors::SchemaError, a_string_including(
                "`next_number` for enum `Status`", "greater than every mapped number", "maximum: 7", "got: 7"
              ))
            end
          end

          describe "protobuf number boundaries" do
            it "accepts maximum numbers while allowing enum values in the field-reserved range" do
              artifact = {
                "messages" => {"Account" => {
                  "fields" => {"id" => proto_field_contract(FieldNumberMappings::MAX_FIELD_NUMBER)},
                  "next_number" => FieldNumberMappings::MAX_FIELD_NUMBER + 1
                }},
                # Enum value numbers have no protobuf-reserved range, so 19000-19999 is fine here.
                "enums" => {"Status" => {"values" => {
                  "ACTIVE" => FieldNumberMappings::MAX_ENUM_VALUE_NUMBER,
                  "INACTIVE" => 19_005
                }, "next_number" => FieldNumberMappings::MAX_ENUM_VALUE_NUMBER + 1}}
              }

              expect(FieldNumberMappings.from_parsed_yaml(artifact).to_dumpable_hash).to eq(artifact)
            end
          end
        end

        describe ".from_yaml_file" do
          it "loads mappings through `FromYamlFile`", :in_temp_dir do
            ::File.write("proto_field_numbers.yaml", <<~YAML)
              messages:
                Account:
                  fields:
                    id:
                      field_number: 7
                      proto_type: string
                      list_depth: 0
                  next_number: 8
              enums:
                Status:
                  values:
                    ACTIVE: 3
                  next_number: 8
            YAML

            mappings = FieldNumberMappings.from_yaml_file("proto_field_numbers.yaml")

            expect(mappings.to_dumpable_hash).to eq({
              "messages" => {"Account" => {"fields" => {"id" => proto_field_contract(7)}, "next_number" => 8}},
              "enums" => {"Status" => {"values" => {"ACTIVE" => 3}, "next_number" => 8}}
            })
          end
        end

        describe "#field_number_for" do
          it "retains a nested-list contract through serialization without changing the input" do
            artifact = {"messages" => {"Account" => {
              "fields" => {"scores" => proto_field_contract(7, "int64", list_depth: 2)}, "next_number" => 10
            }}}
            original = Marshal.load(Marshal.dump(artifact))
            mappings = FieldNumberMappings.from_parsed_yaml(artifact)
            expect(mappings.field_number_for(message_name: "Account", public_field_name: "scores", previous_field_names: [], proto_type: "int64", list_depth: 2)).to eq(7)
            expect(mappings.field_number_for(message_name: "Account", public_field_name: "name", previous_field_names: [], proto_type: "string", list_depth: 0)).to eq(10)
            expect(artifact).to eq(original)
            dumped = mappings.to_dumpable_hash
            expect(dumped.dig("messages", "Account", "fields", "scores")).to eq(proto_field_contract(7, "int64", list_depth: 2))
            expect(FieldNumberMappings.from_parsed_yaml(dumped).to_dumpable_hash).to eq(dumped)
          end

          it "rejects type and list-depth changes before renaming or allocating a number" do
            mappings = FieldNumberMappings.from_parsed_yaml({"messages" => {"Account" => {
              "fields" => {"score" => proto_field_contract(1, "int32")}, "next_number" => 2
            }}})
            original = mappings.to_dumpable_hash
            [["score", [], "int64", 0], ["score", [], "int32", 1], ["points", ["score"], "string", 0]].each do |name, previous_names, proto_type, depth|
              expect {
                mappings.field_number_for(message_name: "Account", public_field_name: name, previous_field_names: previous_names, proto_type: proto_type, list_depth: depth)
              }.to raise_error(Errors::SchemaError, a_string_including("Incompatible protobuf change", "retained int32", "Use a new field name"))
              expect(mappings.to_dumpable_hash).to eq(original)
            end
          end

          it "allocates past protobuf's reserved field-number range" do
            mappings = FieldNumberMappings.from_parsed_yaml({"messages" => {"Account" => {"fields" => {}, "next_number" => 18_999}}})
            expect(mappings.field_number_for(message_name: "Account", public_field_name: "id", previous_field_names: [], proto_type: "string", list_depth: 0)).to eq(18_999)
            expect(mappings.next_field_number_for("Account")).to eq(20_000)
          end

          it "raises a clear error when multiple previous field names have mappings" do
            mappings = FieldNumberMappings.from_parsed_yaml({
              "messages" => {"Account" => {
                "fields" => {"first_name" => proto_field_contract(1), "last_name" => proto_field_contract(2)},
                "next_number" => 3
              }}
            })

            expect {
              mappings.field_number_for(
                message_name: "Account",
                public_field_name: "name",
                previous_field_names: ["last_name", "first_name"],
                proto_type: "string",
                list_depth: 0
              )
            }.to raise_error(Errors::SchemaError, a_string_including(
              "Cannot preserve a protobuf field number for `Account.name`",
              "multiple previous field names have mappings (`first_name` and `last_name`)",
              "use `renamed_from` for the name whose number should carry over and `deleted_field` for the others"
            ))
          end

          it "raises a clear error when the field-number range has been exhausted" do
            mappings = FieldNumberMappings.from_parsed_yaml({
              "messages" => {"Account" => {
                "fields" => {"id" => proto_field_contract(FieldNumberMappings::MAX_FIELD_NUMBER)},
                "next_number" => FieldNumberMappings::MAX_FIELD_NUMBER + 1
              }}
            })

            expect {
              mappings.field_number_for(message_name: "Account", public_field_name: "name", previous_field_names: [], proto_type: "string", list_depth: 0)
            }.to raise_error(Errors::SchemaError, a_string_including(
              "Cannot allocate another protobuf field number for message `Account`",
              "maximum field number (#{FieldNumberMappings::MAX_FIELD_NUMBER}) has been reached"
            ))
          end
        end

        describe "allocation cursor readers" do
          it "returns stored cursors, defaulting to 1 for unmapped messages and enums" do
            mappings = FieldNumberMappings.from_parsed_yaml({
              "messages" => {"Account" => {"fields" => {"id" => proto_field_contract(7)}, "next_number" => 10}},
              "enums" => {"Status" => {"values" => {"ACTIVE" => 3}, "next_number" => 8}}
            })

            expect(mappings.next_field_number_for("Account")).to eq(10)
            expect(mappings.next_field_number_for("UnmappedMessage")).to eq(1)
            expect(mappings.next_enum_value_number_for("Status")).to eq(8)
            expect(mappings.next_enum_value_number_for("UnmappedEnum")).to eq(1)
          end
        end

        describe "#enum_value_numbers_for" do
          it "allocates from the saved cursor without filling gaps" do
            mappings = FieldNumberMappings.from_parsed_yaml({
              "enums" => {"Status" => {"values" => {"ACTIVE" => 3}, "next_number" => 10}}
            })

            expect(mappings.enum_value_numbers_for("Status", ["ARCHIVED", "ACTIVE", "DELETED"])).to eq({
              "ARCHIVED" => 10,
              "ACTIVE" => 3,
              "DELETED" => 11
            })
            expect(mappings.to_dumpable_hash.dig("enums", "Status", "values")).to eq({
              "ACTIVE" => 3,
              "ARCHIVED" => 10,
              "DELETED" => 11
            })
            expect(mappings.next_enum_value_number_for("Status")).to eq(12)
          end

          it "raises a clear error when the enum value-number range has been exhausted" do
            mappings = FieldNumberMappings.from_parsed_yaml({
              "enums" => {"Status" => {
                "values" => {"ACTIVE" => FieldNumberMappings::MAX_ENUM_VALUE_NUMBER},
                "next_number" => FieldNumberMappings::MAX_ENUM_VALUE_NUMBER + 1
              }}
            })

            expect {
              mappings.enum_value_numbers_for("Status", ["ACTIVE", "INACTIVE"])
            }.to raise_error(Errors::SchemaError, a_string_including(
              "Cannot allocate another protobuf enum value number for enum `Status`",
              "maximum enum value number (#{FieldNumberMappings::MAX_ENUM_VALUE_NUMBER}) has been reached"
            ))
          end
        end

        describe "reserved number readers" do
          it "returns mapped names that are not active, ordered by number" do
            mappings = FieldNumberMappings.from_parsed_yaml({
              "messages" => {"Account" => {
                "fields" => {"name" => proto_field_contract(3), "legacy_id" => proto_field_contract(1), "id" => proto_field_contract(2)},
                "next_number" => 4
              }},
              "enums" => {"Status" => {"values" => {"PAUSED" => 2, "ACTIVE" => 1}, "next_number" => 3}}
            })

            reserved_field_numbers = mappings.reserved_field_numbers_for("Account", ["id"])
            expect(reserved_field_numbers).to eq({
              "legacy_id" => 1,
              "name" => 3
            })
            expect(reserved_field_numbers.keys).to eq(["legacy_id", "name"])
            expect(mappings.reserved_enum_value_numbers_for("Status", ["ACTIVE"])).to eq({"PAUSED" => 2})
            expect(mappings.reserved_field_numbers_for("MissingMessage", [])).to eq({})
            expect(mappings.reserved_enum_value_numbers_for("MissingEnum", [])).to eq({})
          end
        end

        describe "#to_dumpable_hash" do
          it "sorts messages and enums by name, and their fields and values by number" do
            mappings = FieldNumberMappings.from_parsed_yaml(
              {
                "messages" => {
                  "ZMessage" => {"fields" => {"first" => proto_field_contract(2), "second" => proto_field_contract(1)}, "next_number" => 3},
                  "AMessage" => {"fields" => {"only" => proto_field_contract(3)}, "next_number" => 4}
                },
                "enums" => {
                  "ZEnum" => {"values" => {"FIRST" => 2, "SECOND" => 1}, "next_number" => 3},
                  "AEnum" => {"values" => {"ONLY" => 3}, "next_number" => 4}
                }
              }
            )

            artifact = mappings.to_dumpable_hash
            expect(artifact.fetch("messages").keys).to eq(["AMessage", "ZMessage"])
            expect(artifact.dig("messages", "ZMessage", "fields").keys).to eq(["second", "first"])
            expect(artifact.dig("messages", "ZMessage", "next_number")).to eq(3)
            expect(artifact.fetch("enums").keys).to eq(["AEnum", "ZEnum"])
            expect(artifact.dig("enums", "ZEnum", "values").keys).to eq(["SECOND", "FIRST"])
            expect(artifact.dig("enums", "ZEnum", "next_number")).to eq(3)
            expect(artifact.dig("enums", "AEnum", "next_number")).to eq(4)
          end
        end
      end
    end
  end
end
