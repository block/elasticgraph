# Copyright 2024 - 2025 Block, Inc.
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
            [MinOrMaxValue.function_def(min_or_max)]
          end

          # @param min_or_max [:min, :max] which type of function to generate.
          # @return [String] painless function for managing a min or max field.
          def self.function_def(min_or_max)
            operator = (min_or_max == :min) ? "<" : ">"

            <<~EOS
              boolean #{min_or_max}Value_idempotentlyUpdateValue(List values, def parentObject, String fieldName) {
                def currentFieldValue = parentObject[fieldName];
                def #{min_or_max}NewValue = values.isEmpty() ? null : Collections.#{min_or_max}(values);

                if (currentFieldValue == null || (#{min_or_max}NewValue != null && #{min_or_max}NewValue.compareTo(currentFieldValue) #{operator} 0)) {
                  parentObject[fieldName] = #{min_or_max}NewValue;
                  return true;
                }

                return false;
              }
            EOS
          end
        end
      end
    end
  end
end
