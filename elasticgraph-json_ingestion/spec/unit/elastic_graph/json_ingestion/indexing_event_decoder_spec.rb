# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/indexer/indexing_event_decoder"
require "elastic_graph/json_ingestion/indexing_event_decoder"
require "elastic_graph/schema_artifacts/runtime_metadata/extension_loader"

module ElasticGraph
  module JSONIngestion
    RSpec.describe IndexingEventDecoder do
      it "decodes newline-delimited JSON objects" do
        decoder = IndexingEventDecoder.new(config: {}, schema_artifacts: nil, logger: nil) # args are not used
        payload = <<~JSONL
          {"op":"upsert","id":"1"}
          {"op":"upsert","id":"2"}
        JSONL

        expect(decoder.decode(payload)).to eq([
          {"op" => "upsert", "id" => "1", INGESTION_FORMAT_KEY => "json"},
          {"op" => "upsert", "id" => "2", INGESTION_FORMAT_KEY => "json"}
        ])
      end

      it "preserves version keys for the ingestion adapter to resolve" do
        decoder = IndexingEventDecoder.new(config: {}, schema_artifacts: nil, logger: nil) # args are not used

        expect(decoder.decode('{"op":"upsert","id":"1","json_schema_version":3,"schema_version":2}')).to eq([
          {"op" => "upsert", "id" => "1", JSON_SCHEMA_VERSION_KEY => 3, SCHEMA_VERSION_KEY => 2, INGESTION_FORMAT_KEY => "json"}
        ])
      end

      it "implements the indexing event decoder interface defined by `elasticgraph-indexer`" do
        loader = SchemaArtifacts::RuntimeMetadata::ExtensionLoader.new(Indexer::IndexingEventDecoder::Interface)

        extension = loader.load(
          "ElasticGraph::JSONIngestion::IndexingEventDecoder",
          from: "elastic_graph/json_ingestion/indexing_event_decoder",
          config: {}
        )

        expect(extension.extension_class).to be(IndexingEventDecoder)
      end
    end
  end
end
