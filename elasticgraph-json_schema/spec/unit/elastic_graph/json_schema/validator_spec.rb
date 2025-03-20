# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/constants"
require "elastic_graph/json_schema/validator"
require "elastic_graph/json_schema/validator_factory"

module ElasticGraph
  module JSONSchema
    RSpec.describe Validator do
      it "does not touch `additionalProperties` by default" do
        validator = validator_for({
          "type" => "object",
          "properties" => {
            "is_happy" => {
              "anyOf" => [
                {"type" => "string"},
                {"type" => "null"}
              ]
            }
          }
        })

        data = {"is_happy" => "yes", "another_property" => 3}

        expect(validator.valid?(data)).to be true
        expect(validator.validate(data).to_a).to be_empty
        expect(validator.validate_with_error_message(data)).to eq nil
      end

      it "can be configured to fail when there are extra properties" do
        validator = validator_for({
          "type" => "object",
          "properties" => {
            "is_happy" => {
              "anyOf" => [
                {"type" => "string"},
                {"type" => "null"}
              ]
            }
          }
        }, &:with_unknown_properties_disallowed)

        data = {"is_happy" => "yes", "another_property" => 3}

        expect(validator.valid?(data)).to be false
        expect(validator.validate(data).to_a).to include(
          a_hash_including("data" => 3, "data_pointer" => "/another_property")
        )
        expect(validator.validate_with_error_message(data)).to include("another_property")
      end

      it "can be configured to fail on extra properties while allowing specific extra properties" do
        validator = validator_for({
          "type" => "object",
          "properties" => {
            "is_happy" => {"type" => "string"},
            "sub_object" => {
              "properties" => {
                "foo" => {"type" => "string"}
              }
            }
          }
        }) do |factory|
          factory.with_unknown_properties_disallowed(except: ["extra1", "sub_object.extra2"])
        end

        valid1 = {"is_happy" => "yes", "sub_object" => {"foo" => "abc"}}
        valid2 = {"is_happy" => "yes", "extra1" => 1, "sub_object" => {"foo" => "abc"}}
        valid3 = {"is_happy" => "yes", "extra1" => 1, "sub_object" => {"foo" => "abc", "extra2" => 1}}

        expect(validator.validate_with_error_message(valid1)).to eq nil
        expect(validator.validate_with_error_message(valid2)).to eq nil
        expect(validator.validate_with_error_message(valid3)).to eq nil

        invalid1 = {"is_happy" => "yes", "extra2" => 1, "sub_object" => {"foo" => "abc"}}
        invalid2 = {"is_happy" => "yes", "sub_object" => {"foo" => "abc", "extra1" => 2}}

        expect(validator.validate_with_error_message(invalid1)).to include("extra2")
        expect(validator.validate_with_error_message(invalid2)).to include("extra1")
      end

      it "does not mutate the schema when applying `additionalProperties: false`" do
        schema = {
          "type" => "object",
          "properties" => {
            "is_happy" => {"type" => "string"},
            "sub_object" => {
              "properties" => {
                "foo" => {"type" => "string"}
              }
            }
          }
        }

        expect {
          validator_for(schema) do |factory|
            factory.with_unknown_properties_disallowed(except: ["extra1", "sub_object.extra2"])
          end
        }.not_to change { schema }
      end

      it "ignores specified extra fields that are already defined in the schema" do
        validator = validator_for({
          "type" => "object",
          "properties" => {
            "is_happy" => {"type" => "string"}
          }
        }) do |factory|
          factory.with_unknown_properties_disallowed(except: ["is_happy"])
        end

        expect(validator.validate_with_error_message({"is_happy" => "yes"})).to eq nil
        expect(validator.validate_with_error_message({"is_happy" => 3})).to include("is_happy")
      end

      it "excludes the given data from validation errors when `sanitize_pii` is `true`" do
        unsanitized_validator = validator_for({
          "type" => "object",
          "properties" => {
            "is_happy" => {"type" => "integer"}
          }
        }, sanitize_pii: false)

        sanitized_validator = unsanitized_validator.with(sanitize_pii: true)

        expect(sanitized_validator.validate_with_error_message({"is_happy" => "pii_value"})).to exclude("pii_value")
        expect(unsanitized_validator.validate_with_error_message({"is_happy" => "pii_value"})).to include("pii_value")
      end

      it "can validate with schemas using type references" do
        validator = validator_for({
          "$defs" => {
            "ID" => {
              "type" => "string",
              "maxLength" => 10
            },
            "MyType" => {
              "type" => "object",
              "properties" => {
                "id" => {
                  "$ref" => "#/$defs/ID"
                }
              }
            }
          }
        }, type_name: "MyType")

        valid_data = {"id" => "my_type_id"}
        expect(validator.valid?(valid_data)).to be true
        expect(validator.validate(valid_data).to_a).to be_empty
        expect(validator.validate_with_error_message(valid_data)).to eq nil

        invalid_data = {"id" => "my_type_id_that_is_way_too_long"}
        expect(validator.valid?(invalid_data)).to be false
        expect(validator.validate(invalid_data).to_a)
          .to contain_exactly(
            {
              "data" => "my_type_id_that_is_way_too_long",
              "data_pointer" => "/id",
              "error" => "string length at `/id` is greater than: 10",
              "schema_pointer" => "/$defs/ID",
              "type" => "maxLength"
            }
          )
        expect(validator.validate_with_error_message(invalid_data)).to include("my_type_id_that_is_way_too_long")
      end

      it "treats regex patterns as ecma does to more closely match standard JSON schema behavior" do
        pattern = /^foo$/
        expect(pattern).to match("before\nfoo\nafter")

        validator = validator_for({
          "$defs" => {
            "MyType" => {
              "type" => "object",
              "properties" => {
                "word" => {
                  "pattern" => pattern.source
                }
              }
            }
          }
        }, type_name: "MyType")

        expect(validator.validate_with_error_message({"word" => "foo"})).to eq nil
        expect(validator.validate_with_error_message({"word" => "before\nfoo\nafter"})).to include('"schema_pointer": "/$defs/MyType/properties/word"')
      end

      def validator_for(schema, type_name: nil, sanitize_pii: false)
        if type_name.nil?
          schema = {"$defs" => {"SomeTypeName" => schema}}
          type_name = "SomeTypeName"
        end

        schema = {"$schema" => JSON_META_SCHEMA}.merge(schema)

        factory = ValidatorFactory.new(schema: schema, sanitize_pii: sanitize_pii)
        factory = yield factory if block_given?
        factory.validator_for(type_name)
      end
    end
  end
end
