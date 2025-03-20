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
        # Responsible for providing bits of the painless script specific to a {DerivedIndexedType#immutable_value} field.
        #
        # @api private
        class ImmutableValue < ::Data.define(:destination_field, :source_field, :nullable, :can_change_from_null)
          # `Data.define` provides the following methods:
          # @dynamic destination_field, source_field

          # @return [String] a line of painless code to manage an immutable value field and return a boolean indicating if it was updated.
          def apply_operation_returning_update_status
            *parent_parts, field = destination_field.split(".")
            parent_parts = ["ctx", "_source"] + parent_parts

            %{immutableValue_idempotentlyUpdateValue(scriptErrors, data["#{source_field}"], #{parent_parts.join(".")}, "#{destination_field}", "#{field}", #{nullable}, #{can_change_from_null})}
          end

          # @return [Array<String>] a list of painless statements that must be called at the top of the script to set things up.
          def setup_statements
            FieldInitializerSupport.build_empty_value_initializers(destination_field, leaf_value: :leave_unset)
          end

          # @return [Array<String>] painless functions required by `immutable_value`.
          def function_definitions
            [IDEMPOTENTLY_SET_VALUE]
          end

          private

          # Painless function which manages an `immutable_value` field.
          IDEMPOTENTLY_SET_VALUE = <<~EOS
            boolean immutableValue_idempotentlyUpdateValue(List scriptErrors, List values, def parentObject, String fullPath, String fieldName, boolean nullable, boolean canChangeFromNull) {
              boolean fieldAlreadySet = parentObject.containsKey(fieldName);

              // `values` is always passed to us as a `List` (the indexer normalizes to a list, wrapping single
              // values in a list as needed) but we only ever expect at most 1 element.
              def newValueCandidate = values.isEmpty() ? null : values[0];

              if (fieldAlreadySet) {
                def currentValue = parentObject[fieldName];

                // Usually we do not allow `immutable_value` fields to ever change values. However, we make
                // a special case for `null`, but only when `can_change_from_null: true` has been configured.
                // This can be important when deriving a field that has not always existed on the source events.
                // On early events, the value may be `null`, and, when this is enabled, we do not want that to
                // interfere with our ability to set the value to the correct non-null value based on a different
                // event which has a value for the source field.
                if (canChangeFromNull) {
                  if (currentValue == null) {
                    parentObject[fieldName] = newValueCandidate;
                    return true;
                  }

                  // When `can_change_from_null: true` is enabled we also need to ignore NEW `null` values that we
                  // see _after_ a non-null value. This is necessary because an ElasticGraph invariant is that events
                  // can be processed in any order. So we might process an old event (predating the existence of the
                  // source field) after we've already set the field to a non-null value. We must always "converge"
                  // on the same indexed state regardless, of the order events are seen, so here we just ignore it.
                  if (newValueCandidate == null) {
                    return false;
                  }
                }

                // Otherwise, if the values differ, it means we are attempting to mutate the immutable value field, which we cannot allow.
                if (currentValue != newValueCandidate) {
                  if (currentValue == null) {
                    scriptErrors.add("Field `" + fullPath + "` cannot be changed (" + currentValue + " => " + newValueCandidate + "). Set `can_change_from_null: true` on the `immutable_value` definition to allow this.");
                  } else {
                    scriptErrors.add("Field `" + fullPath + "` cannot be changed (" + currentValue + " => " + newValueCandidate + ").");
                  }
                }

                return false;
              }

              if (newValueCandidate == null && !nullable) {
                scriptErrors.add("Field `" + fullPath + "` cannot be set to `null`, but the source event contains no value for it. Remove `nullable: false` from the `immutable_value` definition to allow this.");
                return false;
              }

              parentObject[fieldName] = newValueCandidate;
              return true;
            }
          EOS
        end
      end
    end
  end
end
