# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/constants"
require "elastic_graph/indexer/operation/result"
require "elastic_graph/indexer/operation/update_categorization"

module ElasticGraph
  class Indexer
    module Operation
      # Wraps multiple derived `Update` operations targeting the same document into a single
      # bulk operation. This reduces lock contention on hot documents (e.g., `order_merchants`)
      # by merging N scripted updates into 1, concatenating their data param lists.
      #
      # The existing Painless scripts handle lists natively — `minValue_idempotentlyUpdateValue`
      # finds the min of a list, `maxValue_idempotentlyUpdateValue` finds the max, etc. — so
      # concatenating lists from multiple events produces the same result as processing them
      # sequentially, but with a single document lock acquisition instead of N.
      class CoalescedUpdate
        include UpdateCategorization

        attr_reader :source_operations, :doc_id, :destination_index_def, :update_target

        def initialize(operations)
          @source_operations = operations
          first = operations.first
          @doc_id = first.doc_id
          @destination_index_def = first.destination_index_def
          @update_target = first.update_target
        end

        # Delegate event to first source operation. This is used when a single event reference
        # is needed (e.g., for Result tracking). For expanding results back to all source events,
        # use `source_operations` instead.
        def event
          @source_operations.first.event
        end

        def all_events
          @source_operations.map(&:event)
        end

        def type
          :update
        end

        def versioned?
          # Derived updates are never versioned.
          false
        end

        def description
          "#{update_target.type} coalesced update (#{@source_operations.size} events)"
        end

        def inspect
          "#<#{self.class.name} doc_id=#{doc_id} target=#{update_target.type} ops=#{@source_operations.size}>"
        end
        alias_method :to_s, :inspect

        def to_datastore_bulk
          @to_datastore_bulk ||= [{update: metadata}, update_request]
        end

        private

        def metadata
          # All operations in this group share the same index, doc_id, and routing.
          # Use the first operation's metadata.
          @source_operations.first.metadata
        end

        def update_request
          {
            script: {id: update_target.script_id, params: merged_script_params},
            scripted_upsert: true,
            upsert: {}
          }
        end

        def merged_script_params
          all_params = @source_operations.map(&:script_params)

          # Start with a copy of the first operation's params
          merged = all_params.first.dup
          merged_data = merged["data"].transform_values { |v| Array(v).dup }

          # Merge data from remaining operations by concatenating value lists
          all_params[1..].each do |params|
            params["data"].each do |key, values|
              merged_data[key].concat(Array(values))
            end
          end

          merged["data"] = merged_data
          merged
        end
      end
    end
  end
end
