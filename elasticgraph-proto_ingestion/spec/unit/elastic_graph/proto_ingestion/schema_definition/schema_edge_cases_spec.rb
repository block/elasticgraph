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

        it "raises when two fields collapse to the same proto field name after keyword escaping" do
          expect {
            define_proto_schema do |s|
              s.object_type "Account" do |t|
                t.field "id", "ID"
                t.field "string", "String"
                t.field "string_", "String"
                t.index "accounts"
              end
            end
          }.to raise_error(Errors::SchemaError, a_string_including("duplicate proto field names"))
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

          expect(proto.scan(/^enum Status \{/).size).to eq(1)
          expect(proto_type_def_from(proto, "Account")).to include("Status status = 2;")
          expect(proto_type_def_from(proto, "User")).to include("Status status = 2;")
        end
        it "raises on field-number mapping collisions for a message" do
          results = define_proto_schema_results do |s|
            s.configure_proto_field_number_mappings(
              {
                "messages" => {
                  "Account" => {
                    "id" => 1,
                    "name" => 1
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

          expect {
            results.proto_schema
          }.to raise_error(Errors::SchemaError, a_string_including("field-number mapping collision"))
        end

        it "normalizes nil field-number mappings to empty hashes" do
          results = define_proto_schema_results do |s|
            s.configure_proto_field_number_mappings nil
          end

          expect(results.proto_schema).to eq("")
          expect(results.proto_field_number_mappings).to eq({"enums" => {}, "messages" => {}})
        end

        it "validates field-number mapping input type" do
          results = define_proto_schema_results do |s|
            s.configure_proto_field_number_mappings("bad")

            s.object_type "Account" do |t|
              t.field "id", "ID"
              t.index "accounts"
            end
          end

          expect {
            results.proto_schema
          }.to raise_error(Errors::SchemaError, a_string_including("must be a Hash"))
        end

        it "validates that `messages` is a hash in field-number mappings" do
          results = define_proto_schema_results do |s|
            s.configure_proto_field_number_mappings({"messages" => "bad"})

            s.object_type "Account" do |t|
              t.field "id", "ID"
              t.index "accounts"
            end
          end

          expect {
            results.proto_schema
          }.to raise_error(Errors::SchemaError, a_string_including("must have a `messages` Hash"))
        end

        it "accepts symbol `:messages` key in field-number mappings" do
          results = define_proto_schema_results do |s|
            s.configure_proto_field_number_mappings(
              {
                messages: {
                  "Account" => {
                    "id" => 7
                  }
                }
              }
            )

            s.object_type "Account" do |t|
              t.field "id", "ID"
              t.index "accounts"
            end
          end

          expect(results.proto_schema).to include("string id = 7;")
        end

        it "accepts symbol `:fields` and nested symbol keys in field-number mappings" do
          results = define_proto_schema_results do |s|
            s.configure_proto_field_number_mappings(
              {
                messages: {
                  "Account" => {
                    fields: {
                      "id" => {
                        field_number: 7,
                        name_in_index: :account_id
                      }
                    }
                  }
                }
              }
            )

            s.object_type "Account" do |t|
              t.field "id", "ID", name_in_index: "account_id"
              t.index "accounts"
            end
          end

          expect(results.proto_schema).to include("string id = 7;")
        end

        it "validates per-message field-number mapping structure" do
          results = define_proto_schema_results do |s|
            s.configure_proto_field_number_mappings({"messages" => {"Account" => "bad"}})

            s.object_type "Account" do |t|
              t.field "id", "ID"
              t.index "accounts"
            end
          end

          expect {
            results.proto_schema
          }.to raise_error(Errors::SchemaError, a_string_including("must be a Hash"))
        end

        it "validates that nested `fields` is a hash in field-number mappings" do
          results = define_proto_schema_results do |s|
            s.configure_proto_field_number_mappings({"messages" => {"Account" => {"fields" => "bad"}}})

            s.object_type "Account" do |t|
              t.field "id", "ID"
              t.index "accounts"
            end
          end

          expect {
            results.proto_schema
          }.to raise_error(Errors::SchemaError, a_string_including("must contain a `fields` Hash"))
        end

        it "validates that mapped field numbers are valid protobuf field tags" do
          [0, Schema::MAX_FIELD_NUMBER + 1, 19_000, 19_999].each do |invalid_number|
            results = define_proto_schema_results do |s|
              s.configure_proto_field_number_mappings({"messages" => {"Account" => {"id" => invalid_number}}})

              s.object_type "Account" do |t|
                t.field "id", "ID"
                t.index "accounts"
              end
            end

            expect {
              results.proto_schema
            }.to raise_error(Errors::SchemaError, a_string_including(
              "must be a valid protobuf field number", "excluding the reserved 19000-19999 range", invalid_number.to_s
            ))
          end
        end

        it "accepts maximum protobuf numbers while allowing enum values in the field-reserved range" do
          results = define_proto_schema_results do |s|
            s.configure_proto_field_number_mappings(
              {
                "messages" => {"Account" => {"id" => Schema::MAX_FIELD_NUMBER}},
                # Enum value numbers have no protobuf-reserved range, so 19000-19999 is fine here.
                "enums" => {"Status" => {"values" => {
                  "ACTIVE" => Schema::MAX_ENUM_VALUE_NUMBER,
                  "INACTIVE" => 19_005
                }}}
              }
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

          generated = results.proto_schema
          expect(generated).to include("string id = #{Schema::MAX_FIELD_NUMBER};")
          expect(generated).to include("STATUS_ACTIVE = #{Schema::MAX_ENUM_VALUE_NUMBER};")
          expect(generated).to include("STATUS_INACTIVE = 19005;")
        end

        it "skips the protobuf-reserved range when allocating new field numbers" do
          legacy_mappings = (1..18_999).to_h { |number| ["legacy_field_#{number}", number] }

          results = define_proto_schema_results do |s|
            s.configure_proto_field_number_mappings({"messages" => {"Account" => legacy_mappings}})

            s.object_type "Account" do |t|
              t.field "id", "ID"
              t.index "accounts"
            end
          end

          expect(results.proto_schema).to include("string id = 20000;")
        end

        it "validates that mapped enum value numbers do not exceed the int32 maximum" do
          results = define_proto_schema_results do |s|
            s.configure_proto_field_number_mappings(
              {"enums" => {"Status" => {"values" => {"ACTIVE" => Schema::MAX_ENUM_VALUE_NUMBER + 1}}}}
            )

            s.object_type "Account" do |t|
              t.field "id", "ID"
              t.index "accounts"
            end
          end

          expect {
            results.proto_schema
          }.to raise_error(Errors::SchemaError, a_string_including("must be a positive integer no greater than 2147483647"))
        end

        it "validates that mapped field numbers are integers" do
          results = define_proto_schema_results do |s|
            s.configure_proto_field_number_mappings({"messages" => {"Account" => {"id" => "abc"}}})

            s.object_type "Account" do |t|
              t.field "id", "ID"
              t.index "accounts"
            end
          end

          expect {
            results.proto_schema
          }.to raise_error(Errors::SchemaError, a_string_including("must be an integer"))
        end

        it "accepts integer field numbers given as strings" do
          results = define_proto_schema_results do |s|
            s.configure_proto_field_number_mappings({"messages" => {"Account" => {"id" => "7"}}})

            s.object_type "Account" do |t|
              t.field "id", "ID"
              t.index "accounts"
            end
          end

          expect(results.proto_schema).to include("string id = 7;")
        end

        it "accepts symbol `:enums` and `:values` keys and shorthand value hashes in enum value-number mappings" do
          results = define_proto_schema_results do |s|
            s.configure_proto_field_number_mappings(
              {
                enums: {
                  "Status" => {values: {"INACTIVE" => 5}},
                  "Color" => {"RED" => 3}
                }
              }
            )

            s.enum_type "Status" do |t|
              t.values "ACTIVE", "INACTIVE"
            end

            s.enum_type "Color" do |t|
              t.values "RED"
            end

            s.object_type "Account" do |t|
              t.field "id", "ID"
              t.field "status", "Status"
              t.field "color", "Color"
              t.index "accounts"
            end
          end

          generated = results.proto_schema
          expect(generated).to include("STATUS_ACTIVE = 1;", "STATUS_INACTIVE = 5;", "COLOR_RED = 3;")
        end

        it "validates that `enums` is a hash in enum value-number mappings" do
          results = define_proto_schema_results do |s|
            s.configure_proto_field_number_mappings({"enums" => "bad"})

            s.object_type "Account" do |t|
              t.field "id", "ID"
              t.index "accounts"
            end
          end

          expect {
            results.proto_schema
          }.to raise_error(Errors::SchemaError, a_string_including("must have an `enums` Hash"))
        end

        it "validates per-enum value-number mapping structure" do
          results = define_proto_schema_results do |s|
            s.configure_proto_field_number_mappings({"enums" => {"Status" => "bad"}})

            s.object_type "Account" do |t|
              t.field "id", "ID"
              t.index "accounts"
            end
          end

          expect {
            results.proto_schema
          }.to raise_error(Errors::SchemaError, a_string_including("must contain a `values` Hash"))
        end

        it "validates that mapped enum value numbers are positive integers, since 0 is reserved" do
          results = define_proto_schema_results do |s|
            s.configure_proto_field_number_mappings({"enums" => {"Status" => {"values" => {"ACTIVE" => 0}}}})

            s.object_type "Account" do |t|
              t.field "id", "ID"
              t.index "accounts"
            end
          end

          expect {
            results.proto_schema
          }.to raise_error(Errors::SchemaError, a_string_including("must be a positive integer", "_UNSPECIFIED"))
        end

        it "validates that mapped enum value numbers are integers rather than truncating them" do
          results = define_proto_schema_results do |s|
            s.configure_proto_field_number_mappings({"enums" => {"Status" => {"values" => {"ACTIVE" => 1.5}}}})

            s.object_type "Account" do |t|
              t.field "id", "ID"
              t.index "accounts"
            end
          end

          expect {
            results.proto_schema
          }.to raise_error(Errors::SchemaError, a_string_including("must be a positive integer", "1.5"))
        end

        it "validates that structured mappings include `field_number`" do
          results = define_proto_schema_results do |s|
            s.configure_proto_field_number_mappings(
              {"messages" => {"Account" => {"fields" => {"id" => {"name_in_index" => "account_id"}}}}}
            )

            s.object_type "Account" do |t|
              t.field "id", "ID", name_in_index: "account_id"
              t.index "accounts"
            end
          end

          expect {
            results.proto_schema
          }.to raise_error(Errors::SchemaError, a_string_including("must include `field_number`"))
        end

        it "validates that structured mappings use a String or Symbol `name_in_index`" do
          results = define_proto_schema_results do |s|
            s.configure_proto_field_number_mappings(
              {"messages" => {"Account" => {"fields" => {"id" => {"field_number" => 7, "name_in_index" => 123}}}}}
            )

            s.object_type "Account" do |t|
              t.field "id", "ID"
              t.index "accounts"
            end
          end

          expect {
            results.proto_schema
          }.to raise_error(Errors::SchemaError, a_string_including("must use a String or Symbol `name_in_index`"))
        end

        it "defaults structured mappings without `name_in_index` to the field name" do
          results = define_proto_schema_results do |s|
            s.configure_proto_field_number_mappings(
              {"messages" => {"Account" => {"fields" => {"display_name" => {"field_number" => 7}}}}}
            )

            s.object_type "Account" do |t|
              t.field "id", "ID"
              t.field "display_name", "String"
              t.index "accounts"
            end
          end

          expect(results.proto_schema).to include("string display_name = 7;")
        end

        it "allocates the next available field number when a renamed field has no old mapping entry" do
          results = define_proto_schema_results do |s|
            s.configure_proto_field_number_mappings(
              {"messages" => {"Account" => {"fields" => {"other_name" => 7}}}}
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
          expect(results.proto_schema).to include("string display_name = 2;")
        end
      end
    end
  end
end
