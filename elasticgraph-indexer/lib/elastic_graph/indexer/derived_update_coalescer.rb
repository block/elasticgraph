# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/indexer/datastore_indexing_router"
require "elastic_graph/indexer/operation/coalesced_update"
require "elastic_graph/indexer/operation/result"
require "elastic_graph/indexer/operation/update"

module ElasticGraph
  class Indexer
    # Groups derived update operations targeting the same document and merges them into
    # single CoalescedUpdate operations. Normal indexing operations pass through unchanged.
    # This reduces lock contention on hot documents by turning N scripted updates into 1.
    #
    # Create a new instance per batch of operations processed by the `Processor`.
    class DerivedUpdateCoalescer
      IMMUTABLE_VALUE_FUNCTION_NAME = "immutableValue_idempotentlyUpdateValue("

      def initialize(datastore_scripts)
        @coalescable_script_ids = build_coalescable_script_ids(datastore_scripts)
        @coalesced_mapping = {} # : Hash[Operation::CoalescedUpdate, Array[Operation::Update]]
      end

      # Coalesces derived update operations. Returns the (potentially reduced) list of operations.
      def coalesce(operations)
        normal_ops = [] # : Array[Operation::Update]
        derived_groups = ::Hash.new { |h, k| h[k] = [] } # : Hash[Array[untyped], Array[Operation::Update]]

        operations.each do |op|
          if coalescable_derived_update?(op)
            key = [
              op.doc_id,
              op.update_target.script_id,
              routing_and_index_key(op)
            ]
            derived_groups[key] << op
          else
            normal_ops << op
          end
        end

        coalesced_ops = derived_groups.map do |_key, ops|
          if ops.size == 1
            ops.first
          else
            coalesced = Operation::CoalescedUpdate.new(ops)
            @coalesced_mapping[coalesced] = ops
            coalesced
          end
        end

        normal_ops + coalesced_ops
      end

      # Expands results from coalesced operations back to individual operation results.
      # A single CoalescedUpdate success/failure/noop is fanned out to all source operations.
      def expand_results(bulk_result)
        return bulk_result if @coalesced_mapping.empty?

        expanded_ops_and_results = bulk_result.ops_and_results_by_cluster.transform_values do |ops_and_results|
          ops_and_results.flat_map do |(op, result)|
            if (source_ops = @coalesced_mapping[op])
              source_ops.map do |source_op|
                expanded_result = case result.category
                when :success then Operation::Result.success_of(source_op)
                when :noop then Operation::Result.noop_of(source_op, result.description)
                when :failure then Operation::Result.failure_of(source_op, result.description)
                end
                [source_op, expanded_result]
              end
            else
              [[op, result]]
            end
          end
        end

        DatastoreIndexingRouter::BulkResult.new(expanded_ops_and_results)
      end

      private

      # Coalescing is safe only for derived scripts that are associative/commutative under list concatenation.
      # We currently skip scripts that use immutable-value semantics because they require per-event processing order.
      def coalescable_derived_update?(op)
        op.is_a?(Operation::Update) &&
          !op.update_target.for_normal_indexing? &&
          @coalescable_script_ids.key?(op.update_target.script_id)
      end

      # Returns the shard/index targeting fields used by datastore bulk metadata. Operations with different
      # target index or routing cannot be safely coalesced.
      def routing_and_index_key(op)
        metadata = op.metadata
        [metadata[:_index], metadata[:routing]]
      end

      def build_coalescable_script_ids(datastore_scripts)
        datastore_scripts.each_with_object({}) do |(script_id, payload), ids|
          source = payload.dig("script", "source")
          next unless source
          next if source.include?(IMMUTABLE_VALUE_FUNCTION_NAME)
          ids[script_id] = true
        end
      end
    end
  end
end
