# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/indexer/event_id"
require "elastic_graph/indexer/failed_event_error"
require "elastic_graph/indexer/operation/update"
require "elastic_graph/indexer/record_preparer"
require "elastic_graph/support/memoizable_data"

module ElasticGraph
  class Indexer
    module Operation
      class Factory < Support::MemoizableData.define(
        :schema_artifacts,
        :index_definitions_by_graphql_type,
        :ingestion_adapters,
        :logger,
        :skip_derived_indexing_type_updates
      )
        def build(event)
          event = prepare_event(event)

          unless (adapter = ingestion_adapter_for(event))
            return build_failed_result(event, "event payload", "No available ingestion adapter recognized this event.")
          end

          validation_result = adapter.validate_event(event)

          if (failure = validation_result.failure)
            return build_failed_result(event, failure.payload_description, failure.message)
          end

          record_preparer = validation_result.record_preparer # : _RecordPreparer
          BuildResult.success(build_all_operations_for(event, record_preparer))
        end

        private

        # Routes the event to the first ingestion adapter that recognizes it. When exactly one
        # adapter is available, it receives all events--including unrecognizable ones--so that
        # its more specific validation failure messages are used.
        def ingestion_adapter_for(event)
          ingestion_adapters.find { |adapter| adapter.handles_event?(event) } ||
            (ingestion_adapters.first if ingestion_adapters.size == 1)
        end

        # This copies the `id` from event into the actual record
        # This is necessary because we want to index `id` as part of the record so that the datastore will include `id` in returned search payloads.
        def prepare_event(event)
          return event unless event["record"].is_a?(::Hash) && event["id"]
          event.merge("record" => event["record"].merge("id" => event.fetch("id")))
        end

        def build_failed_result(event, payload_description, validation_message)
          message = "Malformed #{payload_description}. #{validation_message}"

          # Here we use the `RecordPreparer::Identity` record preparer because the event failed validation, so
          # no adapter-provided record preparer is available, and we won't wind up using the record preparer
          # for real on these operations, anyway.
          operations = build_all_operations_for(event, RecordPreparer::Identity)

          BuildResult.failure(FailedEventError.new(event: event, operations: operations.to_set, main_message: message))
        end

        def build_all_operations_for(event, record_preparer)
          # If `type` is missing or is not a known type (as indicated by `runtime_metadata` being nil)
          # then we can't build a derived indexing type update operation. That case will only happen when we build
          # operations for an `FailedEventError` rather than to execute.
          return [] unless (type = event["type"])
          return [] unless (runtime_metadata = schema_artifacts.runtime_metadata.object_types_by_name[type])

          runtime_metadata.update_targets.flat_map do |update_target|
            ids_to_skip = skip_derived_indexing_type_updates.fetch(update_target.type, ::Set.new)

            index_definitions_for(update_target.type).flat_map do |destination_index_def|
              operations = Update.operations_for(
                event: event,
                destination_index_def: destination_index_def,
                record_preparer: record_preparer,
                update_target: update_target,
                destination_index_mapping: schema_artifacts.index_mappings_by_index_def_name.fetch(destination_index_def.name)
              )

              operations.reject do |op|
                ids_to_skip.include?(op.doc_id).tap do |skipped|
                  if skipped
                    logger.info({
                      "message_type" => "SkippingUpdate",
                      "message_id" => event["message_id"],
                      "update_target" => update_target.type,
                      "id" => op.doc_id,
                      "event_id" => EventID.from_event(event).to_s
                    })
                  end
                end
              end
            end
          end
        end

        def index_definitions_for(type)
          # If `type` is missing or is not a known type (as indicated by not being in this hash)
          # then we return an empty list. That case will only happen when we build
          # operations for an `FailedEventError` rather than to execute.
          index_definitions_by_graphql_type[type] || []
        end

        # :nocov: -- this should not be called. Instead, it exists to guard against wrongly raising an error from this class.
        def raise(*args)
          super("`raise` was called on `Operation::Factory`, but should not. Instead, use " \
            "`yield build_failed_result(...)` so that we can accumulate all invalid events and allow " \
            "the valid events to still be processed.")
        end
        # :nocov:

        # Return value from `build` that indicates what happened.
        # - If it was successful, `operations` will be a non-empty array of operations and `failed_event_error` will be nil.
        # - If there was a validation issue, `operations` will be an empty array and `failed_event_error` will be non-nil.
        BuildResult = ::Data.define(:operations, :failed_event_error) do
          # @implements BuildResult
          def self.success(operations)
            new(operations, nil)
          end

          def self.failure(failed_event_error)
            new([], failed_event_error)
          end
        end
      end
    end
  end
end
