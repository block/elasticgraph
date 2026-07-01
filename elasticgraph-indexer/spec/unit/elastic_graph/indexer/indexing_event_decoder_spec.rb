# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/indexer/indexing_event_decoder"

module ElasticGraph
  class Indexer
    RSpec.describe IndexingEventDecoder::JSONLines, :capture_logs do
      it "decodes newline-delimited JSON objects" do
        decoder = described_class.new(config: {}, schema_artifacts: nil, logger: logger)
        payload = <<~JSONL
          {"op":"upsert","id":"1"}
          {"op":"upsert","id":"2"}
        JSONL

        expect(decoder.decode(payload)).to eq([
          {"op" => "upsert", "id" => "1"},
          {"op" => "upsert", "id" => "2"}
        ])
      end
    end
  end
end
