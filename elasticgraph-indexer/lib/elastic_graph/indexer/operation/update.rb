# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/constants"
require "elastic_graph/errors"
require "elastic_graph/indexer/event_id"
require "elastic_graph/indexer/operation/count_accumulator"
require "elastic_graph/indexer/operation/result"
require "elastic_graph/support/hash_util"
require "elastic_graph/support/memoizable_data"

module ElasticGraph
  class Indexer
    module Operation
      class Update < Support::MemoizableData.define(:event, :prepared_record, :destination_index_def, :update_target, :doc_id, :destination_index_mapping)
        # @dynamic event, destination_index_def, doc_id

        def self.operations_for(
          event:,
          destination_index_def:,
          record_preparer:,
          update_target:,
          destination_index_mapping:
        )
          prepared_record = record_preparer.prepare_for_index(event["type"], event["record"] || {"id" => event["id"]})

          Support::HashUtil
            .fetch_leaf_values_at_path(prepared_record, update_target.id_source.split("."))
            .reject { |id| id.to_s.strip.empty? }
            .uniq
            .map { |doc_id| new(event, prepared_record, destination_index_def, update_target, doc_id, destination_index_mapping) }
        end

        def to_datastore_bulk
          @to_datastore_bulk ||= [{update: metadata}, update_request]
        end

        def categorize(response)
          update = response.fetch("update")
          status = update.fetch("status")

          if noop_result?(response)
            noop_error_message = message_from_thrown_painless_exception(update)
              &.delete_prefix(UPDATE_WAS_NOOP_MESSAGE_PREAMBLE)

            Result.noop_of(self, noop_error_message)
          elsif (200..299).cover?(status)
            Result.success_of(self)
          else
            error = update.fetch("error")

            further_detail =
              if (more_detail = error["caused_by"])
                # Usually the type/reason details are nested an extra level (`caused_by.caused_by`) but sometimes
                # it's not. I think it's nested when the script itself throws an exception where as it's unnested
                # when the datastore is unable to run the script.
                more_detail = more_detail["caused_by"] if more_detail.key?("caused_by")
                " (#{more_detail["type"]}: #{more_detail["reason"]})"
              else
                "; full response: #{::JSON.pretty_generate(response)}"
              end

            Result.failure_of(self, "#{update_target.script_id}(applied to `#{doc_id}`): #{error.fetch("reason")}#{further_detail}")
          end
        end

        def type
          :update
        end

        def description
          if update_target.type == event.fetch("type")
            "#{update_target.type} update"
          else
            "#{update_target.type} update (from #{event.fetch("type")})"
          end
        end

        def inspect
          "#<#{self.class.name} event=#{EventID.from_event(event)} target=#{update_target.type}>"
        end
        alias_method :to_s, :inspect

        def versioned?
          # We do not track source event versions when applying derived indexing updates, but we do for
          # normal indexing updates, so if the update target is for normal indexing it's a versioned operation.
          update_target.for_normal_indexing?
        end

        private

        # The number of retries of the update script we'll have the datastore attempt on concurrent modification conflicts.
        CONFLICT_RETRIES = 5

        def metadata
          {
            _index: destination_index_def.index_name_for_writes(prepared_record, timestamp_field_path: update_target.rollover_timestamp_value_source),
            _id: doc_id,
            routing: destination_index_def.routing_value_for_prepared_record(
              prepared_record,
              route_with_path: update_target.routing_value_source,
              id_path: update_target.id_source
            ),
            retry_on_conflict: CONFLICT_RETRIES
          }.compact
        end

        def update_request
          {
            script: {id: update_target.script_id, params: script_params},
            # We use a scripted upsert instead of formatting an upsert document because it creates
            # for simpler code. To create the upsert document, we'd have to convert the param
            # values to their "upsert form"--for example, for an `append_only_set` field, the param
            # value is generally a single scalar value while in an upsert document it would need to
            # be a list. By using `scripted_upsert`, we can always just pass the params in a consistent
            # way, and rely on the script to handle the case where it is creating a brand new document.
            scripted_upsert: true,
            upsert: {}
          }
        end

        def noop_result?(response)
          update = response.fetch("update")
          error_message = message_from_thrown_painless_exception(update).to_s
          error_message.start_with?(UPDATE_WAS_NOOP_MESSAGE_PREAMBLE) || update["result"] == "noop"
        end

        def message_from_thrown_painless_exception(update)
          update.dig("error", "caused_by", "caused_by", "reason")
        end

        def script_params
          initial_params = update_target.params_for(
            doc_id: doc_id,
            event: event,
            prepared_record: prepared_record
          )

          # The normal indexing script uses `__counts`. Other indexing scripts (e.g. the ones generated
          # for derived indexing) do not use `__counts` so there's no point in spending effort on computing
          # it. Plus, the logic below raises an exception in that case, so it's important we avoid it.
          return initial_params unless update_target.for_normal_indexing?

          CountAccumulator.merge_list_counts_into(
            initial_params,
            mapping: destination_index_mapping,
            list_counts_field_paths_for_source: destination_index_def.list_counts_field_paths_for_source(update_target.relationship.to_s)
          )
        end
      end
    end
  end
end
