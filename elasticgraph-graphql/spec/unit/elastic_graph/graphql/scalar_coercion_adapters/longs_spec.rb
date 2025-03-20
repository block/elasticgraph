# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "support/scalar_coercion_adapter"

module ElasticGraph
  class GraphQL
    module ScalarCoercionAdapters
      RSpec.describe "JsonSafeLong" do
        include_context "scalar coercion adapter support", "JsonSafeLong"

        context "input coercion" do
          it "accepts an input of the minimum valid JsonSafeLong value" do
            expect_input_value_to_be_accepted(JSON_SAFE_LONG_MIN)
          end

          it "accepts an input of the maximum valid JsonSafeLong value" do
            expect_input_value_to_be_accepted(JSON_SAFE_LONG_MAX)
          end

          it "accepts an input of the JsonSafeLong values in the middle of the range" do
            expect_input_value_to_be_accepted(0)
          end

          it "accepts a valid JsonSafeLong when passed as a string" do
            expect_input_value_to_be_accepted("10012312", as: 10012312)
          end

          it "accepts a `nil` value as-is" do
            expect_input_value_to_be_accepted(nil)
          end

          it "rejects an input that is an unconvertible type" do
            expect_input_value_to_be_rejected(false)
          end

          it "rejects an input that is a convertible type with an invalid value" do
            expect_input_value_to_be_rejected("fourteen")
          end

          it "rejects an input of one less than the minimum valid JsonSafeLong value" do
            expect_input_value_to_be_rejected(JSON_SAFE_LONG_MIN - 1)
          end

          it "rejects an input of one more than the maximum valid JsonSafeLong value" do
            expect_input_value_to_be_rejected(JSON_SAFE_LONG_MAX + 1)
          end
        end

        context "result coercion" do
          it "returns a result of the minimum valid JsonSafeLong value" do
            expect_result_to_be_returned(JSON_SAFE_LONG_MIN)
          end

          it "returns a result of the maximum valid JsonSafeLong value" do
            expect_result_to_be_returned(JSON_SAFE_LONG_MAX)
          end

          it "returns a result of the JsonSafeLong values in the middle of the range" do
            expect_result_to_be_returned(0)
          end

          it "returns a valid JsonSafeLong when it starts as a string" do
            expect_result_to_be_returned("10012312", as: 10012312)
          end

          it "returns `nil` as is" do
            expect_result_to_be_returned(nil)
          end

          it "returns `nil` in place of an unconvertible type" do
            expect_result_to_be_replaced_with_nil(false)
          end

          it "returns `nil` in place of a convertible type with an invalid value" do
            expect_result_to_be_replaced_with_nil("fourteen")
          end

          it "returns `nil` in place of one less than the minimum valid JsonSafeLong value" do
            expect_result_to_be_replaced_with_nil(JSON_SAFE_LONG_MIN - 1)
          end

          it "returns `nil` in place of one more than the maximum valid JsonSafeLong value" do
            expect_result_to_be_replaced_with_nil(JSON_SAFE_LONG_MAX + 1)
          end
        end
      end

      RSpec.describe "LongString" do
        include_context "scalar coercion adapter support", "LongString"

        context "input coercion" do
          it "accepts an input of the minimum valid LongString value as a string" do
            expect_input_value_to_be_accepted_as_a_string(LONG_STRING_MIN)
          end

          it "accepts an input of the maximum valid LongString value as a string" do
            expect_input_value_to_be_accepted_as_a_string(LONG_STRING_MAX)
          end

          it "accepts a `nil` value as-is" do
            expect_input_value_to_be_accepted(nil)
          end

          it "accepts an input of the LongString values in the middle of the range as a string" do
            expect_input_value_to_be_accepted_as_a_string(0)
          end

          it "rejects a valid LongString when passed as a number instead of a string, to guard against the client potentially already having rounded it" do
            expect_input_value_to_be_rejected(0)
          end

          it "rejects an input that is an unconvertible type" do
            expect_input_value_to_be_rejected(false)
          end

          it "rejects an input that is a convertible type with an invalid value" do
            expect_input_value_to_be_rejected("fourteen")
          end

          it "rejects an input of one less than the minimum valid LongString value as a string" do
            expect_input_value_to_be_rejected((LONG_STRING_MIN - 1).to_s)
          end

          it "rejects an input of one more than the maximum valid LongString value as a string" do
            expect_input_value_to_be_rejected((LONG_STRING_MAX + 1).to_s)
          end

          def expect_input_value_to_be_accepted_as_a_string(value)
            expect_input_value_to_be_accepted(value.to_s, as: value)
          end
        end

        context "result coercion" do
          it "returns a result of the minimum valid LongString value" do
            expect_result_to_be_returned_as_a_string(LONG_STRING_MIN)
          end

          it "returns a result of the maximum valid LongString value" do
            expect_result_to_be_returned_as_a_string(LONG_STRING_MAX)
          end

          it "returns a result of the LongString values in the middle of the range" do
            expect_result_to_be_returned_as_a_string(0)
          end

          it "returns a valid LongString when it starts as a string" do
            expect_result_to_be_returned("10012312")
          end

          it "returns `nil` as is" do
            expect_result_to_be_returned(nil)
          end

          it "returns `nil` in place of an unconvertible type" do
            expect_result_to_be_replaced_with_nil(false)
          end

          it "returns `nil` in place of a convertible type with an invalid value" do
            expect_result_to_be_replaced_with_nil("fourteen")
          end

          it "returns `nil` in place of one less than the minimum valid LongString value" do
            expect_result_to_be_replaced_with_nil(LONG_STRING_MIN - 1)
          end

          it "returns `nil` in place of one more than the maximum valid LongString value" do
            expect_result_to_be_replaced_with_nil(LONG_STRING_MAX + 1)
          end

          def expect_result_to_be_returned_as_a_string(value)
            expect_result_to_be_returned(value, as: value.to_s)
          end
        end
      end
    end
  end
end
