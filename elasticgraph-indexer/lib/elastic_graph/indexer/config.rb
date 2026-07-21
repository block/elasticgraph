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
    class Config < Support::Config.define(:latency_slo_thresholds_by_timestamp_in_ms, :skip_derived_indexing_type_updates, :skip_record_validation_for, :extension_modules)
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
          skip_record_validation_for: {
            description: "Map of GraphQL type names to the fraction of records (in `[0.0, 1.0]`) whose " \
              "per-type JSON schema validation should be skipped. `0.0` (or an absent key) validates every record; " \
              "`1.0` skips every record; values in between sample. The decision is deterministic per event id " \
              "(`type:id@vversion`) so the same event makes the same skip decision on retry across indexer pods. " \
              "The event envelope (op, id, type, version, json_schema_version, latency_timestamps) is always " \
              "validated. Intended for backfills of trusted, pre-validated data where skipping the per-record " \
              "schema walk yields meaningful ingest speedups, with a sampled fraction left validated as a canary " \
              "for schema drift. Leave empty for live-traffic ingestion: the datastore mappings will not catch all " \
              "the constraints (regex, enum, min/max, format, abstract-type discriminators) that the JSON schema " \
              "enforces.",
            type: "object",
            patternProperties: {/^[A-Z]\w*$/.source => {type: "number", minimum: 0, maximum: 1}},
            additionalProperties: false,
            default: {}, # : untyped
            examples: [
              {}, # : untyped
              {"Widget" => 0.9, "Component" => 1.0}
            ]
          },
          extension_modules: Support::Config::EXTENSION_MODULE_SCHEMA
        }

      private

      def convert_values(skip_derived_indexing_type_updates:, latency_slo_thresholds_by_timestamp_in_ms:, skip_record_validation_for:, extension_modules:)
        {
          skip_derived_indexing_type_updates: skip_derived_indexing_type_updates.transform_values(&:to_set),
          latency_slo_thresholds_by_timestamp_in_ms: latency_slo_thresholds_by_timestamp_in_ms,
          skip_record_validation_for: skip_record_validation_for.transform_values(&:to_f),
          extension_modules: SchemaArtifacts::RuntimeMetadata::ExtensionLoader.load_component_extensions(extension_modules)
        }
      end
    end
  end
end
