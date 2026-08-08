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
            it "uses a valid JSON schema to reject malformed artifacts" do
              expect(Support::JSONSchema.strict_meta_schema_validator.valid?(FieldNumberMappings::JSON_SCHEMA)).to be(true)

              invalid_artifacts = [
                "bad",
                {"messagez" => {}},
                {"messages" => {"Account" => {"fields" => {"id" => 7}}}},
                {"enums" => {"Status" => {"values" => {"ACTIVE" => 1}}}},
                {"messages" => {"Account" => {"fields" => {"id" => "7"}}}},
                {"messages" => {"Account" => {"fields" => {"id" => 19_000}}}},
                {"messages" => {"Account" => {"fields" => {}, "next_number" => 19_000}}},
                {"enums" => {"Status" => {"values" => {"ACTIVE" => 0}}}},
                {"enums" => {"Status" => {"values" => {}, "next_number" => 0}}}
              ]

              invalid_artifacts.each do |artifact|
                expect {
                  FieldNumberMappings.from_parsed_yaml(artifact)
                }.to raise_error(Errors::SchemaError, a_string_including(
                  "Invalid protobuf field-number mappings", "Validation errors"
                ))
              end
            end
          end

          describe "mapping consistency validation" do
            it "raises clear errors when fields or enum values collide" do
              expect {
                FieldNumberMappings.from_parsed_yaml({
                  "messages" => {"Account" => {"fields" => {"id" => 1, "name" => 1}, "next_number" => 2}}
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
                  "messages" => {"Account" => {"fields" => {"id" => 7}, "next_number" => 7}}
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
                  "fields" => {"id" => FieldNumberMappings::MAX_FIELD_NUMBER},
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
                    id: 7
                  next_number: 8
              enums:
                Status:
                  values:
                    ACTIVE: 3
                  next_number: 8
            YAML

            mappings = FieldNumberMappings.from_yaml_file("proto_field_numbers.yaml")

            expect(mappings.to_dumpable_hash).to eq({
              "messages" => {"Account" => {"fields" => {"id" => 7}, "next_number" => 8}},
              "enums" => {"Status" => {"values" => {"ACTIVE" => 3}, "next_number" => 8}}
            })
          end
        end

        describe "#field_number_for" do
          it "raises a clear error when the field-number range has been exhausted" do
            mappings = FieldNumberMappings.from_parsed_yaml({
              "messages" => {"Account" => {
                "fields" => {"id" => FieldNumberMappings::MAX_FIELD_NUMBER},
                "next_number" => FieldNumberMappings::MAX_FIELD_NUMBER + 1
              }}
            })

            expect {
              mappings.field_number_for(message_name: "Account", public_field_name: "name", previous_field_names: [])
            }.to raise_error(Errors::SchemaError, a_string_including(
              "Cannot allocate another protobuf field number for message `Account`",
              "maximum field number (#{FieldNumberMappings::MAX_FIELD_NUMBER}) has been reached"
            ))
          end
        end

        describe "allocation cursor readers" do
          it "returns stored cursors, defaulting to 1 for unmapped messages and enums" do
            mappings = FieldNumberMappings.from_parsed_yaml({
              "messages" => {"Account" => {"fields" => {"id" => 7}, "next_number" => 10}},
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
                "fields" => {"name" => 3, "legacy_id" => 1, "id" => 2},
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
                  "ZMessage" => {"fields" => {"first" => 2, "second" => 1}, "next_number" => 3},
                  "AMessage" => {"fields" => {"only" => 3}, "next_number" => 4}
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
