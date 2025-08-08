# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/support/json_schema/meta_schema_validator"

module ElasticGraph
  module Support
    module JSONSchema
      RSpec.shared_examples_for "a meta schema validator" do
        it "indicates a valid JSON schema is valid" do
          schema = {
            "type" => "object",
            "properties" => {
              "is_happy" => {
                "anyOf" => [
                  {"type" => "string"},
                  {"type" => "null"}
                ]
              }
            }
          }

          expect(validator.valid?(schema)).to be true
          expect(validator.validate(schema).to_a).to be_empty
          expect(validator.validate_with_error_message(schema)).to eq(nil)
        end

        it "indicates a JSON schema with an invalid value is invalid" do
          schema = {
            "type" => "object",
            "properties" => {
              "is_happy" => {
                "anyOf" => [
                  {"type" => 7},
                  {"type" => "null"}
                ]
              }
            }
          }

          expect(validator.valid?(schema)).to be false
          expect(validator.validate(schema).to_a).to include(
            a_hash_including("data" => 7, "data_pointer" => "/properties/is_happy/anyOf/0/type")
          )
          expect(validator.validate_with_error_message(schema)).to include(
            "/properties/is_happy/anyOf/0/type"
          )
        end

        it "indicates a JSON schema with an unknown field is invalid" do
          schema = {
            "type" => "object",
            "properties" => {
              "is_happy" => {
                "anyOf" => [
                  {"type" => "boolean", "foo" => 3},
                  {"type" => "null"}
                ]
              }
            }
          }

          expect(validator.valid?(schema)).to be false
          expect(validator.validate(schema).to_a).to include(
            a_hash_including("data" => 3, "data_pointer" => "/properties/is_happy/anyOf/0/foo")
          )
          expect(validator.validate_with_error_message(schema)).to include(
            "/properties/is_happy/anyOf/0/foo"
          )
        end
      end

      RSpec.describe "JSONSchema.strict_meta_schema_validator" do
        let(:validator) { JSONSchema.strict_meta_schema_validator }
        include_examples "a meta schema validator"

        it "does not allow extra `ElasticGraph` metadata alongside object property subschemas" do
          schema = {
            "type" => "object",
            "properties" => {
              "is_happy" => {
                "type" => "string",
                "ElasticGraph" => {
                  "type" => "String",
                  "nameInIndex" => "is_happy"
                }
              }
            }
          }

          expect(validator.validate_with_error_message(schema)).to include("/properties/is_happy/ElasticGraph")
        end
      end

      RSpec.describe "JSONSchema.elastic_graph_internal_meta_schema_validator" do
        let(:validator) { JSONSchema.elastic_graph_internal_meta_schema_validator }
        include_examples "a meta schema validator"

        it "allows extra `ElasticGraph` metadata alongside object property subschemas" do
          schema = {
            "type" => "object",
            "properties" => {
              "is_happy" => {
                "type" => "string",
                "ElasticGraph" => {
                  "type" => "String",
                  "nameInIndex" => "is_happy"
                }
              }
            }
          }

          expect(validator.valid?(schema)).to be true
          expect(validator.validate(schema).to_a).to be_empty
          expect(validator.validate_with_error_message(schema)).to eq(nil)
        end

        it "requires all `ElasticGraph` metadata properties" do
          schema = {
            "type" => "object",
            "properties" => {
              "is_happy" => {
                "type" => "string",
                "ElasticGraph" => {
                  "nameInIndex" => "is_happy"
                }
              }
            }
          }
          expect(validator.validate_with_error_message(schema)).to include(
            "/properties/is_happy/ElasticGraph", "type"
          )

          schema = {
            "type" => "object",
            "properties" => {
              "is_happy" => {
                "type" => "string",
                "ElasticGraph" => {
                  "type" => "String"
                }
              }
            }
          }
          expect(validator.validate_with_error_message(schema)).to include(
            "/properties/is_happy/ElasticGraph", "nameInIndex"
          )
        end

        it "validates the type of `ElasticGraph` metadata properties" do
          schema = {
            "type" => "object",
            "properties" => {
              "is_happy" => {
                "type" => "string",
                "ElasticGraph" => {
                  "type" => 7,
                  "nameInIndex" => false
                }
              }
            }
          }

          expect(validator.validate_with_error_message(schema)).to include(
            "/properties/is_happy/ElasticGraph/type",
            "/properties/is_happy/ElasticGraph/nameInIndex"
          )
        end
      end
    end
  end
end
