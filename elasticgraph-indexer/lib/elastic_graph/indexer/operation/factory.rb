# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/constants"
require "elastic_graph/indexer/event_id"
require "elastic_graph/indexer/failed_event_error"
require "elastic_graph/indexer/operation/update"
require "elastic_graph/indexer/record_preparer"
require "elastic_graph/support/memoizable_data"
require "zlib"

module ElasticGraph
  class Indexer
    module Operation
      class Factory < Support::MemoizableData.define(
        :schema_artifacts,
        :index_definitions_by_graphql_type,
        :ingestion_adapters,
        :logger,
        :skip_derived_indexing_type_updates,
        :skip_record_validation_percents_by_type
      )
        def build(event)
          event = prepare_event(event)

          unless (adapter = ingestion_adapter_for(event))
            return build_failed_result(event, "event payload", "No available ingestion adapter recognized this event.")
          end

          skip_record_validation = skip_validation?(event["type"], event)
          validation_result = adapter.validate_event(event, skip_record_validation: skip_record_validation)

          if (failure = validation_result.failure)
            return build_failed_result(event, failure.payload_description, failure.message)
          end

          event = validation_result.event # : event
          record_preparer = validation_result.record_preparer # : _RecordPreparer
          if skip_record_validation
            build_success_result_isolating_malformed_records(event, record_preparer, adapter)
          else
            build_success_result(event, record_preparer, type_with_skipped_validation: nil)
          end
        end

        private

        def build_success_result(event, record_preparer, type_with_skipped_validation:)
          BuildResult.success(
            build_all_operations_for(event, record_preparer),
            type_with_skipped_validation: type_with_skipped_validation
          )
        end

        # Builds the operations for an event whose per-record validation we skipped.
        #
        # Skipping validation means malformed data the schema walk would have rejected surfaces instead as
        # an exception while we build the event's operations, and there is no bounded list of error types to
        # enumerate. So we rescue anything and then run the validation we skipped: the validator tells us
        # whether the data was actually bad, and if it was, hands the caller the same pinpointed message it
        # would have gotten had we validated up front. A clean bill of health from the validator means the
        # error was never about the data (a schema artifact defect, or a bug) and must not be swallowed.
        def build_success_result_isolating_malformed_records(event, record_preparer, adapter)
          build_success_result(event, record_preparer, type_with_skipped_validation: event.fetch("type"))
        rescue => exception
          failure = adapter.validate_event(event).failure
          # `raise` is overridden below to stop this class from *originating* an error instead of returning a
          # `BuildResult`. Here we propagate one that already escaped a collaborator, which is exactly what
          # happens without this rescue, so we deliberately bypass that guard.
          ::Kernel.raise(exception) unless failure
          build_failed_result(event, failure.payload_description, failure.message)
        end

        # Routes the event to the first ingestion adapter that recognizes it. When exactly one
        # adapter is available, it receives all untagged events--including unrecognizable ones--so that
        # its more specific validation failure messages are used.
        def ingestion_adapter_for(event)
          return ingestion_adapters.first if ingestion_adapters.one? && !event.key?(INGESTION_FORMAT_KEY)

          ingestion_adapters.find { |adapter| adapter.handles_event?(event) }
        end

        # This copies the `id` from event into the actual record
        # This is necessary because we want to index `id` as part of the record so that the datastore will include `id` in returned search payloads.
        def prepare_event(event)
          return event unless event["record"].is_a?(::Hash) && event["id"]
          event.merge("record" => event["record"].merge("id" => event.fetch("id")))
        end

        # `Zlib.crc32` returns a value in `[0, 2**32)`. Pre-dividing that space by 100 lets us test a
        # configured percent with a single multiply instead of dividing on every event.
        CRC32_SPACE_PER_PERCENT = (1 << 32) / 100.0

        # Decides whether to skip per-record validation for `event` of `type`. The decision is
        # deterministic per event id: a stable `Zlib.crc32` of `EventID#to_s` maps each event to a
        # point in the CRC32 space, and we skip validation for the configured percentage of that
        # space. Same event id => same decision across pods and retries, so retries never flip a
        # record between validated and skipped. `String#hash` is unsuitable here, as `RUBY_HASH_SEED`
        # is per-process. The `<= 0` and `>= 100` guards keep the endpoints exact, so no float
        # boundary error can make a `0` percent skip a record or a `100` percent validate one.
        def skip_validation?(type, event)
          percent = skip_record_validation_percents_by_type[type]
          return false if percent.nil? || percent <= 0
          return true if percent >= 100
          ::Zlib.crc32(EventID.from_event(event).to_s) < percent * CRC32_SPACE_PER_PERCENT
        end

        def build_failed_result(event, payload_description, validation_message)
          message = "Malformed #{payload_description}. #{validation_message}"

          # Here we use the `RecordPreparer::Identity` record preparer because the event failed validation, so
          # no adapter-provided record preparer is available, and we won't wind up using the record preparer
          # for real on these operations, anyway.
          #
          # Building operations for an event we already know is malformed can itself fail--for example, when the
          # record omits a field an update target derives its id from. Reporting what was malformed matters more
          # than reporting the operations we would have run, and `FailedEventError#operations` is documented to
          # sometimes be empty for exactly this reason, so we fall back to no operations rather than let a second
          # failure mask the first.
          operations = begin
            build_all_operations_for(event, RecordPreparer::Identity)
          rescue => exception
            logger.warn({
              "message_type" => "FailedEventOperationBuildingFailure",
              "message_id" => event["message_id"],
              "event_id" => EventID.from_event(event).to_s,
              "error_class" => exception.class.name,
              "error_message" => exception.message
            })
            [] # : ::Array[operation]
          end

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

        # simplecov:disable -- this should not be called. Instead, it exists to guard against wrongly raising an error from this class.
        def raise(*args)
          super("`raise` was called on `Operation::Factory`, but should not. Instead, use " \
            "`return build_failed_result(...)` so that we can accumulate all invalid events and allow " \
            "the valid events to still be processed.")
        end
        # simplecov:enable

        # Return value from `build` that indicates what happened.
        # - If it was successful, `operations` will be a non-empty array of operations and `failed_event_error` will be nil.
        # - If there was a validation issue, `operations` will be an empty array and `failed_event_error` will be non-nil.
        # - `type_with_skipped_validation` names the event's GraphQL type when per-record validation was skipped
        #   (via `skip_record_validation_percents_by_type`), and is nil otherwise. `Processor` aggregates this
        #   for observability.
        BuildResult = ::Data.define(:operations, :failed_event_error, :type_with_skipped_validation) do
          # @implements BuildResult
          def self.success(operations, type_with_skipped_validation: nil)
            new(operations, nil, type_with_skipped_validation)
          end

          def self.failure(failed_event_error)
            new([], failed_event_error, nil)
          end
        end
      end
    end
  end
end
