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
      RSpec.describe "Cursor" do
        include_context "scalar coercion adapter support", "Cursor"

        context "input coercion" do
          it "accepts a properly encoded string cursor" do
            cursor = DecodedCursor.new({"a" => 1, "b" => "foo"})
            expect_input_value_to_be_accepted(cursor.encode, as: cursor)
          end

          it "accepts an already decoded cursor" do
            cursor = DecodedCursor.new({"a" => 1, "b" => "foo"})
            expect_input_value_to_be_accepted(cursor, only_test_variable: true)
          end

          it "accepts the special singleton cursor string value" do
            expect_input_value_to_be_accepted(DecodedCursor::SINGLETON.encode, as: DecodedCursor::SINGLETON)
          end

          it "accepts the special singleton cursor value" do
            expect_input_value_to_be_accepted(DecodedCursor::SINGLETON, only_test_variable: true)
          end

          it "accepts a `nil` value as-is" do
            expect_input_value_to_be_accepted(nil)
          end

          it "rejects values that are not strings" do
            expect_input_value_to_be_rejected(3)
            expect_input_value_to_be_rejected(3.7)
            expect_input_value_to_be_rejected(false)
            expect_input_value_to_be_rejected([1, 2, 3])
            expect_input_value_to_be_rejected(["a", "b"])
            expect_input_value_to_be_rejected({"a" => 1, "b" => "foo"})
          end

          it "rejects broken string cursors" do
            cursor = DecodedCursor.new({"a" => 1, "b" => "foo"}).encode
            expect_input_value_to_be_rejected(cursor + "-broken")
          end
        end

        context "result coercion" do
          it "returns the encoded form of a decoded string cursor" do
            cursor = DecodedCursor.new({"a" => 1, "b" => "foo"})
            expect_result_to_be_returned(cursor, as: cursor.encode)
          end

          it "returns a properly encoded cursor as-is" do
            cursor = DecodedCursor.new({"a" => 1, "b" => "foo"})
            expect_result_to_be_returned(cursor.encode, as: cursor.encode)
          end

          it "returns the encoded form of the special singleton cursor" do
            cursor = DecodedCursor::SINGLETON
            expect_result_to_be_returned(cursor, as: cursor.encode)
          end

          it "returns the encoded form of the special singleton cursor as-is when given in its string form" do
            cursor = DecodedCursor::SINGLETON
            expect_result_to_be_returned(cursor.encode, as: cursor.encode)
          end

          it "returns `nil` as is" do
            expect_result_to_be_returned(nil)
          end

          it "returns `nil` for non-string values" do
            expect_result_to_be_replaced_with_nil(3)
            expect_result_to_be_replaced_with_nil(3.7)
            expect_result_to_be_replaced_with_nil(false)
            expect_result_to_be_replaced_with_nil([1, 2, 3])
            expect_result_to_be_replaced_with_nil(["a", "b"])
            expect_result_to_be_replaced_with_nil({"a" => 1, "b" => "foo"})
          end

          it "returns `nil` for strings that are not properly encoded cursors" do
            expect_result_to_be_replaced_with_nil("not a cursor")
          end
        end
      end
    end
  end
end
