# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/schema_definition/indexing/derived_fields/field_initializer_support"

module ElasticGraph
  module SchemaDefinition
    module Indexing
      module DerivedFields
        # Responsible for providing bits of the painless script specific to a {DerivedIndexedType#append_only_set} field.
        #
        # @api private
        class AppendOnlySet < ::Data.define(:destination_field, :source_field)
          # `Data.define` provides the following methods:
          # @dynamic destination_field, source_field

          # @return [Array<String>] painless functions required by `append_only_set`.
          def function_definitions
            [IDEMPOTENTLY_INSERT_VALUES, IDEMPOTENTLY_INSERT_VALUE]
          end

          # @return [String] a line of painless code to append a value to the set and return a boolean indicating if the set was updated.
          def apply_operation_returning_update_status
            %{appendOnlySet_idempotentlyInsertValues(data["#{source_field}"], ctx._source.#{destination_field})}
          end

          # The statements here initialize the field to an empty list if it is null. This primarily happens when the document
          # does not already exist, but can also happen when we add a new derived field to an existing type.
          #
          # @return [Array<String>] a list of painless statements that must be called at the top of the script to set things up.
          def setup_statements
            FieldInitializerSupport.build_empty_value_initializers(destination_field, leaf_value: FieldInitializerSupport::EMPTY_PAINLESS_LIST)
          end

          private

          IDEMPOTENTLY_INSERT_VALUES = <<~EOS
            // Wrapper around `idempotentlyInsertValue` that handles a list of values.
            // Returns `true` if the list field was updated.
            boolean appendOnlySet_idempotentlyInsertValues(List values, List sortedList) {
              boolean listUpdated = false;

              for (def value : values) {
                listUpdated = appendOnlySet_idempotentlyInsertValue(value, sortedList) || listUpdated;
              }

              return listUpdated;
            }
          EOS

          IDEMPOTENTLY_INSERT_VALUE = <<~EOS
            // Idempotently inserts the given value in the `sortedList`, returning `true` if the list was updated.
            boolean appendOnlySet_idempotentlyInsertValue(def value, List sortedList) {
              // As per https://docs.oracle.com/en/java/javase/11/docs/api/java.base/java/util/Collections.html#binarySearch(java.util.List,java.lang.Object):
              //
              // > Returns the index of the search key, if it is contained in the list; otherwise, (-(insertion point) - 1).
              // > The insertion point is defined as the point at which the key would be inserted into the list: the index
              // > of the first element greater than the key, or list.size() if all elements in the list are less than the
              // > specified key. Note that this guarantees that the return value will be >= 0 if and only if the key is found.
              int binarySearchResult = Collections.binarySearch(sortedList, value);

              if (binarySearchResult < 0) {
                sortedList.add(-binarySearchResult - 1, value);
                return true;
              } else {
                return false;
              }
            }
          EOS
        end
      end
    end
  end
end
