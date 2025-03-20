# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "support/scalar_coercion_adapter"
require "time"

module ElasticGraph
  class GraphQL
    module ScalarCoercionAdapters
      RSpec.describe "Untyped" do
        include_context "scalar coercion adapter support", "Untyped"

        context "input coercion" do
          it "accepts integers" do
            expect_input_value_to_be_accepted(12, as: "12")
          end

          it "accepts floating point numbers" do
            expect_input_value_to_be_accepted(-3.75, as: "-3.75")
          end

          it "accepts strings" do
            expect_input_value_to_be_accepted("foo", as: "\"foo\"")
          end

          it "accepts booleans" do
            expect_input_value_to_be_accepted(true, as: "true")
            expect_input_value_to_be_accepted(false, as: "false")
          end

          it "accepts nil" do
            expect_input_value_to_be_accepted(nil)
          end

          it "accepts arrays of JSON primitives" do
            expect_input_value_to_be_accepted([true, "abc", 75, nil], as: "[true,\"abc\",75,null]")
          end

          it "accepts a JSON object" do
            expect_input_value_to_be_accepted({"name" => "John"}, as: "{\"name\":\"John\"}")
          end

          it "rejects types that are not valid in JSON" do
            expect_input_value_to_be_rejected(::Time.iso8601("2022-12-01T00:00:00Z"), only_test_variable: true)
          end

          it "orders object keys alphabetically when dumping it to normalize to a canonical form" do
            expect_input_value_to_be_accepted({"b" => 1, "a" => 2, "c" => 3}, as: '{"a":2,"b":1,"c":3}')
          end
        end

        context "result coercion" do
          it "returns an integer when given an integer as a JSON string" do
            expect_result_to_be_returned("12", as: 12)
          end

          it "returns a float when given a float as a JSON string" do
            expect_result_to_be_returned("-3.75", as: -3.75)
          end

          it "returns a string when given a string as a JSON string" do
            expect_result_to_be_returned("\"foo\"", as: "foo")
          end

          it "returns a boolean when given a boolean as a JSON string" do
            expect_result_to_be_returned("true", as: true)
            expect_result_to_be_returned("false", as: false)
          end

          it "returns nil as-is" do
            expect_result_to_be_returned(nil)
          end

          it "returns an array of JSON primitives when given that as a JSON string" do
            expect_result_to_be_returned("[true,\"abc\",75,null]", as: [true, "abc", 75, nil])
          end

          it "returns a hash when given that as a JSON string" do
            expect_result_to_be_returned("{\"name\":\"John\"}", as: {"name" => "John"})
          end

          it "rejects values that are not JSON strings (or nil)" do
            expect_result_to_be_replaced_with_nil(3)
            expect_result_to_be_replaced_with_nil(true)
            expect_result_to_be_replaced_with_nil(false)
            expect_result_to_be_replaced_with_nil(3.7)
            expect_result_to_be_replaced_with_nil(Time.now)
            expect_result_to_be_replaced_with_nil(["abc"])
            expect_result_to_be_replaced_with_nil({"name" => "John"})
          end
        end
      end
    end
  end
end
