# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/schema_definition/indexing/derived_fields/min_or_max_value"

module ElasticGraph
  module SchemaDefinition
    module Indexing
      module DerivedFields
        RSpec.describe MinOrMaxValue do
          describe ".function_def" do
            it "compares candidate values with `<` for a `min` field" do
              function_def = MinOrMaxValue.function_def(:min)

              expect(function_def).to include("boolean minValue_idempotentlyUpdateValue(List values, def parentObject, String fieldName)")
              expect(function_def).to include("minOrMaxValue_compareValues(value, minValue) < 0")
            end

            it "compares candidate values with `>` for a `max` field" do
              function_def = MinOrMaxValue.function_def(:max)

              expect(function_def).to include("boolean maxValue_idempotentlyUpdateValue(List values, def parentObject, String fieldName)")
              expect(function_def).to include("minOrMaxValue_compareValues(value, maxValue) > 0")
            end

            it "stores the original winning value without coercing it, to avoid corrupting the indexed value" do
              expect(MinOrMaxValue.function_def(:min)).to include("parentObject[fieldName] = minValue;").and exclude("longValue", "doubleValue")
              expect(MinOrMaxValue.function_def(:max)).to include("parentObject[fieldName] = maxValue;").and exclude("longValue", "doubleValue")
            end
          end

          describe "the `minOrMaxValue_compareValues` painless function" do
            it "compares integral values as `long`s to preserve full precision while avoiding `ClassCastException` on mixed `Integer`/`Long` values" do
              expect(MinOrMaxValue::COMPARE_VALUES).to include("Long.compare(((Number)value1).longValue(), ((Number)value2).longValue())")
            end

            it "compares as `double`s when either value is a floating point number, to avoid truncating fractional parts" do
              expect(MinOrMaxValue::COMPARE_VALUES).to include(
                "value1 instanceof Float || value1 instanceof Double || value2 instanceof Float || value2 instanceof Double",
                "Double.compare(((Number)value1).doubleValue(), ((Number)value2).doubleValue())"
              )
            end

            it "compares non-numeric values (e.g. `Date`/`DateTime`/`LocalTime` strings) via their natural `compareTo`" do
              expect(MinOrMaxValue::COMPARE_VALUES).to include("return value1.compareTo(value2);")
            end
          end

          describe "#function_definitions" do
            it "includes the comparison function so that the min/max function can use it" do
              field = MinOrMaxValue.new("min_cost", "cost", :min)

              expect(field.function_definitions).to eq [
                MinOrMaxValue::COMPARE_VALUES,
                MinOrMaxValue.function_def(:min)
              ]
            end
          end
        end
      end
    end
  end
end
