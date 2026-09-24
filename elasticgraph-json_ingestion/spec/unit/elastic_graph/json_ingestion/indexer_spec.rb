# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/indexer/config"
require "elastic_graph/indexer/malformed_event_error"
require "elastic_graph/json_ingestion/indexer"

module ElasticGraph
  module JSONIngestion
    RSpec.describe Indexer, :builds_indexer, :factories do
      let(:indexer) { Indexer.new(build_indexer) }
      let(:payload) do
        <<~JSONL
          {"op":"upsert","id":"1"}
          {"op":"upsert","id":"2"}
        JSONL
      end
      let(:events) do
        [
          {"op" => "upsert", "id" => "1"},
          {"op" => "upsert", "id" => "2"}
        ]
      end

      it "builds around a format-neutral indexer from parsed YAML" do
        result = Indexer.from_parsed_yaml(parsed_test_settings_yaml)

        expect(result.indexer).to be_a(ElasticGraph::Indexer)
      end

      it "rejects a format-neutral indexer with JSON schema artifacts but no JSON ingestion adapter" do
        base_indexer = build_indexer
        base_indexer.ingestion_adapters_by_format.delete("json")
        expect(base_indexer.schema_artifacts.available_json_schema_versions).not_to be_empty

        expect {
          Indexer.new(base_indexer)
        }.to raise_error Errors::ConfigError, a_string_including(
          "requires JSON schema artifacts and a `json` ingestion adapter",
          "ElasticGraph::JSONIngestion::SchemaDefinition::APIExtension",
          "regenerate the schema artifacts"
        )
      end

      it "rejects a format-neutral indexer with a JSON ingestion adapter but no JSON schema artifacts" do
        schema_artifacts = instance_double(SchemaArtifacts::FromDisk, available_json_schema_versions: [], runtime_metadata: stock_schema_artifacts.runtime_metadata)
        base_indexer = build_indexer(schema_artifacts: schema_artifacts)
        expect(base_indexer.ingestion_adapters_by_format).to include("json")

        expect {
          Indexer.new(base_indexer)
        }.to raise_error Errors::ConfigError, a_string_including(
          "requires JSON schema artifacts and a `json` ingestion adapter",
          "ElasticGraph::JSONIngestion::SchemaDefinition::APIExtension",
          "regenerate the schema artifacts"
        )
      end

      it "exposes the format-neutral indexer dependencies" do
        expect_to_return_non_nil_values_from_all_attributes(indexer)
      end

      it "can decode a payload without processing it" do
        expect(indexer.decode(payload)).to eq(events)
      end

      # We deliberately construct the wrapped indexer here without going through `build_indexer`. The
      # `skip_record_validation_percents_by_type` knob is intentionally not exposed via spec helpers so that
      # tests cannot silently weaken validation; enabling it must be a visible, deliberate choice
      # in each spec that exercises it.
      context "when the indexer is configured to skip record validation for a type" do
        let(:indexer) do
          Indexer.new(ElasticGraph::Indexer.new(
            datastore_core: build_datastore_core,
            config: ElasticGraph::Indexer::Config.new(
              latency_slo_thresholds_by_timestamp_in_ms: {},
              skip_derived_indexing_type_updates: {},
              skip_record_validation_percents_by_type: {"Component" => 100}
            )
          ))
        end

        it "still applies envelope-level validation, since skipping record validation does not bypass envelope validation" do
          event = build_upsert_event_hash(:component, id: "1", __version: -1)

          failures = indexer.process_returning_failures([event])

          expect(failures.map(&:class)).to eq [ElasticGraph::Indexer::MalformedEventError]
          expect(failures.first.message).to include("/properties/version")
        end
      end
    end
  end
end
