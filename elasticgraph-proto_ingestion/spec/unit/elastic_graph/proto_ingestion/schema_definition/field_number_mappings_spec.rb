# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/proto_ingestion/schema_definition/field_number_mappings"

module ElasticGraph
  module ProtoIngestion
    module SchemaDefinition
      RSpec.describe FieldNumberMappings do
        describe ".from_artifact" do
          it "returns empty mappings for `nil`, as parsing an empty artifact file yields" do
            mappings = FieldNumberMappings.from_artifact(nil)

            expect(mappings.to_artifact).to eq({"enums" => {}, "messages" => {}})
          end

          it "validates that the artifact is a hash" do
            expect {
              FieldNumberMappings.from_artifact("bad")
            }.to raise_error(Errors::SchemaError, a_string_including("must be a Hash"))
          end

          it "rejects unknown keys at every level so hand-edit typos do not silently discard mappings" do
            [
              [{"messagez" => {}}, "\"messagez\""],
              [{messages: {}}, ":messages"],
              [{"messages" => {"Account" => {"fieldz" => {}}}}, "\"fieldz\""],
              [{"messages" => {"Account" => {"fields" => {"id" => {"field_number" => 1, "name_in_indexx" => "x"}}}}}, "\"name_in_indexx\""],
              [{"enums" => {"Status" => {"valuez" => {}}}}, "\"valuez\""]
            ].each do |artifact, unknown_key|
              expect {
                FieldNumberMappings.from_artifact(artifact)
              }.to raise_error(Errors::SchemaError, a_string_including("Unknown key(s)", unknown_key))
            end
          end

          it "validates that `messages` is a hash" do
            expect {
              FieldNumberMappings.from_artifact({"messages" => "bad"})
            }.to raise_error(Errors::SchemaError, a_string_including("must have a `messages` Hash"))
          end

          it "validates that each message's mapping is a hash" do
            expect {
              FieldNumberMappings.from_artifact({"messages" => {"Account" => "bad"}})
            }.to raise_error(Errors::SchemaError, a_string_including("mapping for message `Account` must be a Hash"))
          end

          it "validates that each message's nested `fields` is a hash" do
            expect {
              FieldNumberMappings.from_artifact({"messages" => {"Account" => {"fields" => "bad"}}})
            }.to raise_error(Errors::SchemaError, a_string_including("must contain a `fields` Hash"))
          end

          it "validates that mapped field numbers are valid protobuf field tags" do
            [0, FieldNumberMappings::MAX_FIELD_NUMBER + 1, 19_000, 19_999].each do |invalid_number|
              expect {
                FieldNumberMappings.from_artifact({"messages" => {"Account" => {"fields" => {"id" => invalid_number}}}})
              }.to raise_error(Errors::SchemaError, a_string_including(
                "must be a valid protobuf field number", "excluding the reserved 19000-19999 range", invalid_number.to_s
              ))
            end
          end

          it "rejects field numbers given as strings rather than coercing them" do
            ["abc", "7"].each do |non_integer|
              expect {
                FieldNumberMappings.from_artifact({"messages" => {"Account" => {"fields" => {"id" => non_integer}}}})
              }.to raise_error(Errors::SchemaError, a_string_including("must be an integer", non_integer.inspect))
            end
          end

          it "rejects field numbers that are not integers rather than silently truncating them" do
            expect {
              FieldNumberMappings.from_artifact({"messages" => {"Account" => {"fields" => {"id" => 1.5}}}})
            }.to raise_error(Errors::SchemaError, a_string_including("`Account.id`", "must be an integer", "1.5"))
          end

          it "raises a clear error when two fields of a message are mapped to the same number" do
            expect {
              FieldNumberMappings.from_artifact({"messages" => {"Account" => {"fields" => {"id" => 1, "name" => 1}}}})
            }.to raise_error(Errors::SchemaError, a_string_including(
              "field-number mapping collision in message `Account`",
              "`id` and `name`",
              "number 1"
            ))
          end

          it "validates that structured field mappings include `field_number`" do
            expect {
              FieldNumberMappings.from_artifact({"messages" => {"Account" => {"fields" => {"id" => {"name_in_index" => "account_id"}}}}})
            }.to raise_error(Errors::SchemaError, a_string_including("must include `field_number`"))
          end

          it "validates that structured field mappings use a String `name_in_index`" do
            expect {
              FieldNumberMappings.from_artifact({"messages" => {"Account" => {"fields" => {"id" => {"field_number" => 7, "name_in_index" => 123}}}}})
            }.to raise_error(Errors::SchemaError, a_string_including("must use a String `name_in_index`"))
          end

          it "defaults a structured field mapping without `name_in_index` to the field name" do
            mappings = FieldNumberMappings.from_artifact(
              {"messages" => {"Account" => {"fields" => {"display_name" => {"field_number" => 7}}}}}
            )

            expect(mappings.to_artifact.dig("messages", "Account", "fields")).to eq({"display_name" => 7})
          end

          it "accepts maximum protobuf numbers while allowing enum values in the field-reserved range" do
            artifact = {
              "messages" => {"Account" => {"fields" => {"id" => FieldNumberMappings::MAX_FIELD_NUMBER}}},
              # Enum value numbers have no protobuf-reserved range, so 19000-19999 is fine here.
              "enums" => {"Status" => {"values" => {
                "ACTIVE" => FieldNumberMappings::MAX_ENUM_VALUE_NUMBER,
                "INACTIVE" => 19_005
              }}}
            }

            expect(FieldNumberMappings.from_artifact(artifact).to_artifact).to eq(artifact)
          end

          it "validates that `enums` is a hash" do
            expect {
              FieldNumberMappings.from_artifact({"enums" => "bad"})
            }.to raise_error(Errors::SchemaError, a_string_including("must have an `enums` Hash"))
          end

          it "validates that each enum's mapping is a hash" do
            expect {
              FieldNumberMappings.from_artifact({"enums" => {"Status" => "bad"}})
            }.to raise_error(Errors::SchemaError, a_string_including("mapping for enum `Status` must be a Hash"))
          end

          it "validates that each enum's nested `values` is a hash" do
            expect {
              FieldNumberMappings.from_artifact({"enums" => {"Status" => {"values" => "bad"}}})
            }.to raise_error(Errors::SchemaError, a_string_including("must contain a `values` Hash"))
          end

          it "validates that mapped enum value numbers are positive integers, since 0 is reserved" do
            expect {
              FieldNumberMappings.from_artifact({"enums" => {"Status" => {"values" => {"ACTIVE" => 0}}}})
            }.to raise_error(Errors::SchemaError, a_string_including("must be a positive integer", "_UNSPECIFIED"))
          end

          it "validates that mapped enum value numbers do not exceed the int32 maximum" do
            expect {
              FieldNumberMappings.from_artifact(
                {"enums" => {"Status" => {"values" => {"ACTIVE" => FieldNumberMappings::MAX_ENUM_VALUE_NUMBER + 1}}}}
              )
            }.to raise_error(Errors::SchemaError, a_string_including("must be a positive integer no greater than 2147483647"))
          end

          it "rejects enum value numbers given as strings rather than coercing them" do
            expect {
              FieldNumberMappings.from_artifact({"enums" => {"Status" => {"values" => {"ACTIVE" => "5"}}}})
            }.to raise_error(Errors::SchemaError, a_string_including("must be a positive integer", "\"5\""))
          end

          it "rejects enum value numbers that are not integers rather than silently truncating them" do
            expect {
              FieldNumberMappings.from_artifact({"enums" => {"Status" => {"values" => {"ACTIVE" => 1.5}}}})
            }.to raise_error(Errors::SchemaError, a_string_including("must be a positive integer", "1.5"))
          end

          it "raises a clear error when two values of an enum are mapped to the same number" do
            expect {
              FieldNumberMappings.from_artifact({"enums" => {"Status" => {"values" => {"ACTIVE" => 1, "INACTIVE" => 1}}}})
            }.to raise_error(Errors::SchemaError, a_string_including(
              "enum value-number mapping collision in enum `Status`",
              "`ACTIVE` and `INACTIVE`",
              "number 1"
            ))
          end
        end

        describe "#to_artifact" do
          it "sorts messages and enums by name, and their fields and values by number" do
            mappings = FieldNumberMappings.from_artifact(
              {
                "messages" => {
                  "ZMessage" => {"fields" => {"first" => 2, "second" => 1}},
                  "AMessage" => {"fields" => {"only" => 3}}
                },
                "enums" => {
                  "ZEnum" => {"values" => {"FIRST" => 2, "SECOND" => 1}},
                  "AEnum" => {"values" => {"ONLY" => 3}}
                }
              }
            )

            artifact = mappings.to_artifact
            expect(artifact.fetch("messages").keys).to eq(["AMessage", "ZMessage"])
            expect(artifact.dig("messages", "ZMessage", "fields").keys).to eq(["second", "first"])
            expect(artifact.fetch("enums").keys).to eq(["AEnum", "ZEnum"])
            expect(artifact.dig("enums", "ZEnum", "values").keys).to eq(["SECOND", "FIRST"])
          end
        end
      end
    end
  end
end
