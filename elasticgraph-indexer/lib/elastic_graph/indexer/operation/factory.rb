# Copyright 2024 - 2025 Block, Inc.
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
require "elastic_graph/support/json_schema/validator_factory"
require "elastic_graph/support/memoizable_data"

module ElasticGraph
  class Indexer
    module Operation
      class Factory < Support::MemoizableData.define(
        :schema_artifacts,
        :index_definitions_by_graphql_type,
        :record_preparer_factory,
        :logger,
        :skip_derived_indexing_type_updates,
        :configure_record_validator
      )
        def build(event)
          event = prepare_event(event)

          selected_json_schema_version = select_json_schema_version(event) { |failure| return failure }

          # Because the `select_json_schema_version` picks the closest-matching json schema version, the incoming
          # event might not match the expected json_schema_version value in the json schema (which is a `const` field).
          # This is by design, since we're picking a schema based on best-effort, so to avoid that by-design validation error,
          # performing the envelope validation on a "patched" version of the event.
          event_with_patched_envelope = event.merge({JSON_SCHEMA_VERSION_KEY => selected_json_schema_version})

          if (error_message = validator(EVENT_ENVELOPE_JSON_SCHEMA_NAME, selected_json_schema_version).validate_with_error_message(event_with_patched_envelope))
            return build_failed_result(event, "event payload", error_message)
          end

          failed_result = validate_record_returning_failure(event, selected_json_schema_version)
          failed_result || BuildResult.success(build_all_operations_for(
            event,
            record_preparer_factory.for_json_schema_version(selected_json_schema_version)
          ))
        end

        private

        def select_json_schema_version(event)
          available_json_schema_versions = schema_artifacts.available_json_schema_versions

          requested_json_schema_version = event[JSON_SCHEMA_VERSION_KEY]

          # First check that a valid value has been requested (a positive integer)
          if !event.key?(JSON_SCHEMA_VERSION_KEY)
            yield build_failed_result(event, JSON_SCHEMA_VERSION_KEY, "Event lacks a `#{JSON_SCHEMA_VERSION_KEY}`")
          elsif !requested_json_schema_version.is_a?(Integer) || requested_json_schema_version < 1
            yield build_failed_result(event, JSON_SCHEMA_VERSION_KEY, "#{JSON_SCHEMA_VERSION_KEY} (#{requested_json_schema_version}) must be a positive integer.")
          end

          # The requested version might not necessarily be available (if the publisher is deployed ahead of the indexer, or an old schema
          # version is removed prematurely, or an indexer deployment is rolled back). So the behavior is to always pick the closest-available
          # version. If there's an exact match, great. Even if not an exact match, if the incoming event payload conforms to the closest match,
          # the event can still be indexed.
          #
          # This min_by block will take the closest version in the list. If a tie occurs, the first value in the list wins. The desired
          # behavior is in the event of a tie (highly unlikely, there shouldn't be a gap in available json schema versions), the higher version
          # should be selected. So to get that behavior, the list is sorted in descending order.
          #
          selected_json_schema_version = available_json_schema_versions.sort.reverse.min_by { |it| (requested_json_schema_version - it).abs }

          if selected_json_schema_version != requested_json_schema_version
            logger.info({
              "message_type" => "ElasticGraphMissingJSONSchemaVersion",
              "message_id" => event["message_id"],
              "event_id" => EventID.from_event(event),
              "event_type" => event["type"],
              "requested_json_schema_version" => requested_json_schema_version,
              "selected_json_schema_version" => selected_json_schema_version
            })
          end

          if selected_json_schema_version.nil?
            yield build_failed_result(
              event, JSON_SCHEMA_VERSION_KEY,
              "Failed to select json schema version. Requested version: #{event[JSON_SCHEMA_VERSION_KEY]}. \
              Available json schema versions: #{available_json_schema_versions.sort.join(", ")}"
            )
          end

          selected_json_schema_version
        end

        def validator(type, selected_json_schema_version)
          factory = validator_factories_by_version[selected_json_schema_version] # : Support::JSONSchema::ValidatorFactory
          factory.validator_for(type)
        end

        def validator_factories_by_version
          @validator_factories_by_version ||= ::Hash.new do |hash, json_schema_version|
            factory = Support::JSONSchema::ValidatorFactory.new(
              schema: schema_artifacts.json_schemas_for(json_schema_version),
              sanitize_pii: true
            )
            factory = configure_record_validator.call(factory) if configure_record_validator
            hash[json_schema_version] = factory
          end
        end

        # This copies the `id` from event into the actual record
        # This is necessary because we want to index `id` as part of the record so that the datastore will include `id` in returned search payloads.
        def prepare_event(event)
          return event unless event["record"].is_a?(::Hash) && event["id"]
          event.merge("record" => event["record"].merge("id" => event.fetch("id")))
        end

        def validate_record_returning_failure(event, selected_json_schema_version)
          record = event.fetch("record")
          graphql_type_name = event.fetch("type")
          validator = validator(graphql_type_name, selected_json_schema_version)

          if (error_message = validator.validate_with_error_message(record))
            build_failed_result(event, "#{graphql_type_name} record", error_message)
          end
        end

        def build_failed_result(event, payload_description, validation_message)
          message = "Malformed #{payload_description}. #{validation_message}"

          # Here we use the `RecordPreparer::Identity` record preparer because we may not have a valid JSON schema
          # version number in this case (which is usually required to get a `RecordPreparer` from the factory), and
          # we won't wind up using the record preparer for real on these operations, anyway.
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
