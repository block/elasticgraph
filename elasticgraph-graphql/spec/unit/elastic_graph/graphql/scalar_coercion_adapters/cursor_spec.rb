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
          it "accepts string values" do
            expect_input_value_to_be_accepted("abc123")
          end

          it "accepts nil" do
            expect_input_value_to_be_accepted(nil)
          end

          it "rejects non-string values" do
            expect_input_value_to_be_rejected(123)
            expect_input_value_to_be_rejected([1, 2, 3])
            expect_input_value_to_be_rejected({"key" => "value"})
            expect_input_value_to_be_rejected(true)
            expect_input_value_to_be_rejected(false)
          end
        end

        context "result coercion" do
          it "returns string values as-is" do
            expect_result_to_be_returned("abc123", as: "abc123")
          end

          it "returns nil as-is" do
            expect_result_to_be_returned(nil)
          end
        end
      end
    end
  end
end
