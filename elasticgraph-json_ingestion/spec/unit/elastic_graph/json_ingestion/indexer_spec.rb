# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/json_ingestion/indexer"
require "elastic_graph/schema_definition/test_support"

module ElasticGraph
  module JSONIngestion
    RSpec.describe Indexer, :builds_indexer do
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
        expect(base_indexer.schema_artifacts.extension_artifacts.fetch("json").available_json_schema_versions).not_to be_empty

        expect {
          Indexer.new(base_indexer)
        }.to raise_error Errors::ConfigError, a_string_including(
          "requires JSON schema artifacts and a `json` ingestion adapter",
          "ElasticGraph::JSONIngestion::SchemaDefinition::APIExtension",
          "regenerate the schema artifacts"
        )
      end

      it "rejects a format-neutral indexer with a JSON ingestion adapter but no JSON schema artifacts" do
        schema_artifacts = build_indexer.schema_artifacts
        allow(schema_artifacts.extension_artifacts.fetch("json")).to receive(:available_json_schema_versions).and_return(Set.new)
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

      it "rejects in-memory artifacts without JSON support even when a JSON adapter is registered" do
        schema_artifacts = ElasticGraph::SchemaDefinition::TestSupport.define_schema(
          schema_element_name_form: :snake_case,
          extension_modules: []
        ) do |schema|
          schema.register_indexer_extension IndexerExtension, defined_at: "elastic_graph/json_ingestion/indexer_extension"
          schema.object_type "Widget" do |type|
            type.field "id", "ID!"
            type.index "widgets"
          end
        end
        base_indexer = build_indexer(schema_artifacts: schema_artifacts)

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
    end
  end
end
