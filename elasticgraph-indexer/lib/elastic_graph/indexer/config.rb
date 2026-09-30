# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/schema_artifacts/runtime_metadata/extension_loader"
require "elastic_graph/support/config"

module ElasticGraph
  class Indexer
    class Config < Support::Config.define(:latency_slo_thresholds_by_timestamp_in_ms, :skip_derived_indexing_type_updates, :skip_record_validation_percents_by_type, :conflict_retries, :conflict_retries_by_type, :extension_modules)
      json_schema at: "indexer",
        optional: false,
        description: "Configuration for indexing operations and metrics used by `elasticgraph-indexer`.",
        properties: {
          latency_slo_thresholds_by_timestamp_in_ms: {
            description: "Map of indexing latency thresholds (in milliseconds), keyed by the name of " \
              "the indexing latency metric. When an event is indexed with an indexing latency " \
              "exceeding the threshold, a warning with the event type, id, and version will " \
              "be logged, so the issue can be investigated.",
            type: "object",
            patternProperties: {/.+/.source => {type: "integer", minimum: 0}},
            default: {}, # : untyped
            examples: [
              {}, # : untyped
              {"ingested_from_topic_at" => 10000, "entity_updated_at" => 15000}
            ]
          },
          skip_derived_indexing_type_updates: {
            description: "Setting that can be used to specify some derived indexing type updates that should be skipped. This " \
              "setting should be a map keyed by the name of the derived indexing type, and the values should be sets " \
              'of ids. This can be useful when you have a "hot spot" of a single derived document that is ' \
              "receiving a ton of updates. During a backfill (or whatever) you may want to skip the derived " \
              "type updates.",
            type: "object",
            patternProperties: {/^[A-Z]\w*$/.source => {type: "array", items: {type: "string", minLength: 1}}},
            default: {}, # : untyped
            examples: [
              {}, # : untyped
              {"WidgetWorkspace" => ["ABC12345678"]}
            ]
          },
          skip_record_validation_percents_by_type: {
            description: "Map of GraphQL type names to the percentage of records of that type whose per-record " \
              "schema validation should be skipped. `0` (or an absent key) validates every record of the " \
              "type; `100` skips every record; values in between sample, and may be fractional. The decision is " \
              "deterministic per event id (`type:id@vversion`), so the same event makes the same choice on every " \
              "retry and on every indexer pod. Each ingestion adapter always validates its event envelope, " \
              "regardless of this setting.\n\n" \
              "With a large schema the per-record schema walk consumes a significant share of indexing CPU: every " \
              "record is checked against every regex, enum, min/max, format, and abstract-type discriminator " \
              "defined for its type. Skipping it trades that check for throughput, which is worthwhile when " \
              "backfilling data that was already validated upstream. Leaving a percentage of records validated " \
              "keeps a canary in place so schema drift still surfaces.\n\n" \
              "Note: skipping validation makes malformed-data detection later and less precise. A malformation " \
              "found while building an event's operations is still reported as an isolated event failure, carrying " \
              "the message validation itself would have produced. But one found only while serializing an " \
              "operation for the datastore (an unparsable rollover index timestamp, or a missing custom routing " \
              "field) raises an error that fails the entire batch, including the well-formed events in it. Since " \
              "such a batch produces no partial-failure response, the queue redelivers all of its events, and the " \
              "malformed record fails them again on each retry until it is drained to the dead letter queue. Leave " \
              "this empty for live-traffic ingestion.",
            type: "object",
            patternProperties: {/^[A-Z]\w*$/.source => {type: "number", minimum: 0, maximum: 100}},
            additionalProperties: false,
            default: {}, # : untyped
            examples: [
              {}, # : untyped
              {"Widget" => 90, "Component" => 100}
            ]
          },
          conflict_retries: {
            description: "Number of times the datastore retries an update when another write modifies the " \
              "target document between the update's read and its write (the `retry_on_conflict` parameter of " \
              "the bulk update API). An update that exhausts its retries fails with a version conflict and is " \
              "reported as a failed event.\n\n" \
              "A higher value can help when many events update the same document concurrently, such as derived " \
              "indexing or `sourced_from` fields fed by many source events. Each retry re-reads the document and " \
              "re-runs the update script, though, so the datastore work spent on a contended document grows with " \
              "this value.",
            type: "integer",
            minimum: 0,
            default: 5,
            examples: [5, 15]
          },
          conflict_retries_by_type: {
            description: "Overrides `conflict_retries` for updates to documents of the named types. Keys are the " \
              "type of the document being updated, which for derived indexing and `sourced_from` is the destination " \
              "type rather than the type of the event. Types not listed use `conflict_retries`.",
            type: "object",
            patternProperties: {/^[A-Z]\w*$/.source => {type: "integer", minimum: 0}},
            additionalProperties: false,
            default: {}, # : untyped
            examples: [
              {}, # : untyped
              {"Widget" => 15}
            ]
          },
          extension_modules: Support::Config::EXTENSION_MODULE_SCHEMA
        }

      # @param type [String] name of the type whose documents are being updated
      # @return [Integer] the `retry_on_conflict` budget for updates to documents of that type
      def conflict_retries_for(type)
        conflict_retries_by_type.fetch(type, conflict_retries)
      end

      private

      def convert_values(skip_derived_indexing_type_updates:, latency_slo_thresholds_by_timestamp_in_ms:, skip_record_validation_percents_by_type:, conflict_retries:, conflict_retries_by_type:, extension_modules:)
        {
          skip_derived_indexing_type_updates: skip_derived_indexing_type_updates.transform_values(&:to_set),
          latency_slo_thresholds_by_timestamp_in_ms: latency_slo_thresholds_by_timestamp_in_ms,
          skip_record_validation_percents_by_type: skip_record_validation_percents_by_type.transform_values(&:to_f),
          conflict_retries: conflict_retries,
          conflict_retries_by_type: conflict_retries_by_type,
          extension_modules: SchemaArtifacts::RuntimeMetadata::ExtensionLoader.load_component_extensions(extension_modules)
        }
      end
    end
  end
end
