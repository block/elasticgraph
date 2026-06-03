# Copyright 2024 - 2026 Block, Inc.
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
            encoded = cursor.encode
            expect_input_value_to_be_accepted(encoded)
          end

          it "accepts the special singleton cursor string value" do
            encoded = DecodedCursor::SINGLETON.encode
            expect_input_value_to_be_accepted(encoded)
          end

          it "accepts a `nil` value" do
            expect_input_value_to_be_accepted(nil)
          end

          it "accepts broken string cursors" do
            cursor = DecodedCursor.new({"a" => 1, "b" => "foo"}).encode
            broken_cursor = cursor + "-broken"
            expect_input_value_to_be_accepted(broken_cursor)
          end
        end

        context "result coercion" do
          it "returns a properly encoded cursor string" do
            cursor = DecodedCursor.new({"a" => 1, "b" => "foo"})
            encoded = cursor.encode
            expect_result_to_be_returned(encoded, as: encoded)
          end

          it "returns the singleton cursor string" do
            encoded = DecodedCursor::SINGLETON.encode
            expect_result_to_be_returned(encoded, as: encoded)
          end

          it "returns `nil`" do
            expect_result_to_be_returned(nil)
          end
        end
      end
    end
  end
end
