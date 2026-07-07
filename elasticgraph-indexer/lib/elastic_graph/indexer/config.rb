# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/errors"
require "elastic_graph/indexer/indexing_event_decoder"
require "elastic_graph/schema_artifacts/runtime_metadata/extension_loader"
require "elastic_graph/support/config"

module ElasticGraph
  class Indexer
    class Config < Support::Config.define(:latency_slo_thresholds_by_timestamp_in_ms, :skip_derived_indexing_type_updates, :indexing_event_decoder)
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
          indexing_event_decoder: {
            description: "Extension object used to decode raw indexing payloads into ElasticGraph indexing event hashes. " \
              "Required when using a transport that delivers encoded payloads (such as the SQS lambdas). Ingestion " \
              "format gems provide decoder implementations.",
            type: ["object", "null"],
            properties: {
              name: {
                description: "The name of the indexing event decoder extension class.",
                type: "string",
                pattern: /^[A-Z]\w+(::[A-Z]\w+)*$/.source, # https://rubular.com/r/UuqAz4fR3kdMip
                examples: ["MyCompany::ElasticGraph::CSVIndexingEventDecoder"]
              },
              require_path: {
                description: "The path to require to load the indexing event decoder extension.",
                type: "string",
                minLength: 1,
                examples: ["./lib/my_company/elastic_graph/csv_indexing_event_decoder"]
              },
              config: {
                description: "Configuration for the indexing event decoder. Will be passed into the decoder's `#initialize` method.",
                type: "object",
                default: {}, # : untyped
                examples: [
                  {}, # : untyped
                  {"delimiter" => ","}
                ]
              }
            },
            required: ["name", "require_path"],
            default: nil,
            examples: [
              {
                "name" => "MyCompany::ElasticGraph::CSVIndexingEventDecoder",
                "require_path" => "./lib/my_company/elastic_graph/csv_indexing_event_decoder",
                "config" => {"delimiter" => ","}
              }
            ]
          }
        }

      private

      def convert_values(skip_derived_indexing_type_updates:, latency_slo_thresholds_by_timestamp_in_ms:, indexing_event_decoder:)
        {
          skip_derived_indexing_type_updates: skip_derived_indexing_type_updates.transform_values(&:to_set),
          latency_slo_thresholds_by_timestamp_in_ms: latency_slo_thresholds_by_timestamp_in_ms,
          indexing_event_decoder: load_indexing_event_decoder(indexing_event_decoder)
        }
      end

      def load_indexing_event_decoder(config)
        return nil if config.nil?

        loader = SchemaArtifacts::RuntimeMetadata::ExtensionLoader.new(IndexingEventDecoder::Interface)
        loader.load(
          config.fetch("name"),
          from: config.fetch("require_path"),
          config: config["config"] || {}
        )
      end
    end
  end
end
