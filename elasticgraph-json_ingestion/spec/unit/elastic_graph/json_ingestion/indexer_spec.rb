# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/json_ingestion/indexer"

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

      it "exposes the format-neutral indexer dependencies" do
        expect_to_return_non_nil_values_from_all_attributes(indexer)
      end

      it "can decode a payload without processing it" do
        expect(indexer.decode(payload)).to eq(events)
      end
    end
  end
end
