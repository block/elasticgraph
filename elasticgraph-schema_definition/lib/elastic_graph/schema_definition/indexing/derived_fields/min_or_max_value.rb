# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  module SchemaDefinition
    module Indexing
      module DerivedFields
        # Responsible for providing bits of the painless script specific to a {DerivedIndexedType#min_value} or
        # {DerivedIndexedType#max_value} field.
        #
        # @api private
        class MinOrMaxValue < ::Data.define(:destination_field, :source_field, :min_or_max)
          # `Data.define` provides the following methods:
          # @dynamic destination_field, source_field, min_or_max

          # @return [String] a line of painless code to manage a min or max value field and return a boolean indicating if it was updated.
          def apply_operation_returning_update_status
            *parent_parts, field = destination_field.split(".")
            parent_parts = ["ctx", "_source"] + parent_parts

            %{#{min_or_max}Value_idempotentlyUpdateValue(data["#{source_field}"], #{parent_parts.join(".")}, "#{field}")}
          end

          # @return [Array<String>] a list of painless statements that must be called at the top of the script to set things up.
          def setup_statements
            FieldInitializerSupport.build_empty_value_initializers(destination_field, leaf_value: :leave_unset)
          end

          # @return [Array<String>] painless functions required by a min or max value field.
          def function_definitions
            [COMPARE_VALUES, MinOrMaxValue.function_def(min_or_max)]
          end

          # @param min_or_max [:min, :max] which type of function to generate.
          # @return [String] painless function for managing a min or max field.
          def self.function_def(min_or_max)
            operator = (min_or_max == :min) ? "<" : ">"

            <<~EOS
              boolean #{min_or_max}Value_idempotentlyUpdateValue(List values, def parentObject, String fieldName) {
                def currentFieldValue = parentObject[fieldName];

                // Track the winning value itself (rather than a coerced copy of it) so that the exact value
                // from the source event or existing document gets stored, with no coercion applied.
                def #{min_or_max}Value = currentFieldValue;
                boolean updated = false;

                for (def value : values) {
                  if (value != null && (#{min_or_max}Value == null || minOrMaxValue_compareValues(value, #{min_or_max}Value) #{operator} 0)) {
                    #{min_or_max}Value = value;
                    updated = true;
                  }
                }

                if (updated) {
                  parentObject[fieldName] = #{min_or_max}Value;
                }

                return updated;
              }
            EOS
          end

          private

          # Painless function which compares two values of a min or max field, coercing numeric values as needed.
          COMPARE_VALUES = <<~EOS
            // Compares two values of a min or max field, coercing numeric values as needed.
            //
            // Different `Number` implementations (e.g. `Integer` vs `Long`, or `Long` vs `Double`) cannot be
            // compared with `compareTo` (it throws a `ClassCastException`), and JSON parsing can produce any
            // of them for the same field (e.g. `2` parses as an `Integer` while `2.9` parses as a `Double`).
            // Integral values are compared as `long`s to preserve full precision (a `double` cannot exactly
            // represent all integral values above 2^53), while comparisons involving a floating point value
            // are performed as `double`s to avoid truncating fractional parts.
            int minOrMaxValue_compareValues(def value1, def value2) {
              if (value1 instanceof Number && value2 instanceof Number) {
                if (value1 instanceof Float || value1 instanceof Double || value2 instanceof Float || value2 instanceof Double) {
                  return Double.compare(((Number)value1).doubleValue(), ((Number)value2).doubleValue());
                }

                return Long.compare(((Number)value1).longValue(), ((Number)value2).longValue());
              }

              return value1.compareTo(value2);
            }
          EOS
        end
      end
    end
  end
end
