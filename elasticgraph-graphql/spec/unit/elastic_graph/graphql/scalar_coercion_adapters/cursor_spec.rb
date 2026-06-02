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
          it "accepts a properly encoded string cursor and returns it as a string" do
            cursor = DecodedCursor.new({"a" => 1, "b" => "foo"})
            encoded = cursor.encode
            expect_input_value_to_be_accepted(encoded, as: encoded)
          end

          it "accepts the special singleton cursor string value and returns it as a string" do
            encoded = DecodedCursor::SINGLETON.encode
            expect_input_value_to_be_accepted(encoded, as: encoded)
          end

          it "accepts a `nil` value as-is" do
            expect_input_value_to_be_accepted(nil)
          end

          it "accepts broken string cursors (validation deferred to Paginator)" do
            cursor = DecodedCursor.new({"a" => 1, "b" => "foo"}).encode
            broken_cursor = cursor + "-broken"
            # Coercion passes it through; Paginator will raise InvalidCursorError when decoding
            expect_input_value_to_be_accepted(broken_cursor, as: broken_cursor)
          end
        end

        context "result coercion" do
          # Note: Resolvers always return already-encoded cursor strings (via Edge#cursor
          # which calls DecodedCursor#encode), so coerce_result just passes values through.
          # These tests verify the pass-through behavior.

          it "returns a properly encoded cursor string as-is" do
            cursor = DecodedCursor.new({"a" => 1, "b" => "foo"})
            encoded = cursor.encode
            expect_result_to_be_returned(encoded, as: encoded)
          end

          it "returns the singleton cursor string as-is" do
            encoded = DecodedCursor::SINGLETON.encode
            expect_result_to_be_returned(encoded, as: encoded)
          end

          it "returns `nil` as-is" do
            expect_result_to_be_returned(nil)
          end
        end
      end
    end
  end
end
