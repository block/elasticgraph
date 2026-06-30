# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/json_ingestion/indexing_event_decoder"

module ElasticGraph
  module JSONIngestion
    RSpec.describe IndexingEventDecoder::JSONLines do
      it "decodes newline-delimited JSON objects" do
        decoder = described_class.new(config: {}, schema_artifacts: nil, logger: nil)
        payload = <<~JSONL
          {"op":"upsert","id":"1"}
          {"op":"upsert","id":"2"}
        JSONL

        expect(decoder.decode(payload)).to eq([
          {"op" => "upsert", "id" => "1"},
          {"op" => "upsert", "id" => "2"}
        ])
      end

      it "maps json_schema_version to the indexer's generic schema_version key" do
        decoder = described_class.new(config: {}, schema_artifacts: nil, logger: nil)

        expect(decoder.decode('{"op":"upsert","id":"1","json_schema_version":3}')).to eq([
          {"op" => "upsert", "id" => "1", SCHEMA_VERSION_KEY => 3}
        ])
      end
    end
  end
end
