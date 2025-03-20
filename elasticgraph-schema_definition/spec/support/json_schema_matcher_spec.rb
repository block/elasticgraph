# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/constants"
require "support/json_schema_matcher"

# Note: this spec exists to verify our custom JSON schema matcher works
# properly. It doesn't really validate ElasticGraph itself, and if it
# becomes a burden to maintain, consider deleting it.
RSpec.describe "JSON schema matcher", aggregate_failures: false do
  it "passes when the schema is valid and the same" do
    type = "MyType"
    schema = {
      "type" => "object",
      "properties" => {
        "id" => {
          "anyOf" => [
            {"type" => "string"},
            {"type" => "null"}
          ]
        }
      },
      "required" => %w[id]
    }

    expect(schema_with(type, schema)).to have_json_schema_like(type, schema, include_typename: false)
  end

  it "treats string and symbol keys as equivalent because they dump the same" do
    string_key_schema = {
      "type" => "object",
      "properties" => {
        "name" => {"type" => "string"}
      }
    }

    symbol_key_schema = {
      type: "object",
      properties: {
        "name" => {type: "string"}
      }
    }

    schema = {
      "$schema" => ::ElasticGraph::JSON_META_SCHEMA,
      "$defs" => {
        "StringType" => string_key_schema,
        "SymbolType" => symbol_key_schema
      }
    }

    expect(schema).to have_json_schema_like("StringType", symbol_key_schema, include_typename: false)
    expect(schema).to have_json_schema_like("SymbolType", string_key_schema, include_typename: false)
  end

  it "fails when the expected schema has an invalid value" do
    type = "InvalidType"
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

    expect {
      expect(schema_with(type, schema)).to have_json_schema_like(type, schema)
    }.to fail_with("but got validation errors")
  end

  it "fails when the expected schema has an unknown field" do
    type = "InvalidType"
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

    expect {
      expect(schema_with(type, schema)).to have_json_schema_like(type, schema)
    }.to fail_with("but got validation errors")
  end

  it "fails when the expected and actual schemas are different but both valid" do
    schema1 = {
      "type" => "object",
      "properties" => {
        "is_happy" => {
          "anyOf" => [
            {"type" => "boolean"},
            {"type" => "null"}
          ]
        }
      }
    }

    schema2 = {
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

    schema = {
      "$schema" => ::ElasticGraph::JSON_META_SCHEMA,
      "$defs" => {
        "Type1" => schema1,
        "Type2" => schema2
      }
    }

    expect {
      expect(schema).to have_json_schema_like("Type1", schema2)
    }.to fail_with("but got JSON schema")
  end

  it "uses the validator that allows extra `ElasticGraph` metadata in the JSON schema" do
    type = "MyType"
    schema = {
      "type" => "object",
      "properties" => {
        "id" => {
          "anyOf" => [
            {"type" => "string"},
            {"type" => "null"}
          ],
          "ElasticGraph" => {
            "type" => "String",
            "nameInIndex" => "id"
          }
        }
      },
      "required" => %w[id]
    }

    expect(schema_with(type, schema)).to have_json_schema_like(type, schema, include_typename: false)
  end

  context "when `which_matches(...).and_fails_to_match(...)` is used" do
    type = "Type"
    schema = {"type" => "number"}

    it "passes when it correctly matches or fails to match as specified" do
      expect(schema_with(type, schema)).to have_json_schema_like(type, schema)
        .which_matches(1, 2, 3).and_fails_to_match("foo", "bar", nil)
    end

    it "fails when one of the expected matches does not match" do
      expect {
        expect(schema_with(type, schema)).to have_json_schema_like(type, schema)
          .which_matches(1, "bar", 3).and_fails_to_match("foo", "bazz", nil)
      }.to fail_with("Failure at index 1 from payload", "bar")
    end

    it "fails when one of the expected non matches does match" do
      expect {
        expect(schema_with(type, schema)).to have_json_schema_like(type, schema)
          .which_matches(1, 2, 3).and_fails_to_match("foo", "bar", nil, 17)
      }.to fail_with("Failure at index 3 from payload", "17")
    end
  end

  def schema_with(type, schema)
    {"$schema" => ::ElasticGraph::JSON_META_SCHEMA, "$defs" => {type => schema}}
  end

  def fail_with(*snippets)
    raise_error(::RSpec::Expectations::ExpectationNotMetError, a_string_including(*snippets))
  end
end
