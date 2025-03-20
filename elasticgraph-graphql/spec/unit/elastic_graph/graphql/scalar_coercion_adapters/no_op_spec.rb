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
      RSpec.describe "NoOp" do
        include_context("scalar coercion adapter support", "SomeCustomScalar", schema_definition: ->(schema) do
          schema.scalar_type "SomeCustomScalar" do |t|
            t.json_schema type: "null"
            t.mapping type: nil
          end

          schema.object_type "Widget" do |t|
            t.field "id", "ID!"
            t.field "scalar", "SomeCustomScalar"
            t.index "widgets"
          end
        end)

        context "input coercion" do
          it "leaves values of any type unmodified" do
            expect_input_value_to_be_accepted(nil)
            expect_input_value_to_be_accepted(3)
            expect_input_value_to_be_accepted(3.7)
            expect_input_value_to_be_accepted(false)
            expect_input_value_to_be_accepted("foo")
            expect_input_value_to_be_accepted([1, 2, 3])
            expect_input_value_to_be_accepted(["a", "b"])
            expect_input_value_to_be_accepted({"a" => 1, "b" => "foo"})
          end
        end

        context "result coercion" do
          it "leaves values of any type unmodified" do
            expect_result_to_be_returned(nil)
            expect_result_to_be_returned(3)
            expect_result_to_be_returned(3.7)
            expect_result_to_be_returned(false)
            expect_result_to_be_returned("foo")
            expect_result_to_be_returned([1, 2, 3])
            expect_result_to_be_returned(["a", "b"])
            expect_result_to_be_returned({"a" => 1, "b" => "foo"})
          end
        end
      end
    end
  end
end
