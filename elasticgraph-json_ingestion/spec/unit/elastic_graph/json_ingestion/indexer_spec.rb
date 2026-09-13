# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/indexer/failed_event_error"
require "elastic_graph/indexer/processor"
require "elastic_graph/json_ingestion/indexer"

module ElasticGraph
  module JSONIngestion
    RSpec.describe Indexer do
      let(:processor) { instance_double(ElasticGraph::Indexer::Processor, process: nil, process_returning_failures: failures) }
      let(:failures) { [] }
      let(:base_indexer) do
        instance_double(
          ElasticGraph::Indexer,
          config: :config,
          datastore_core: :datastore_core,
          logger: :logger,
          processor: processor,
          schema_artifacts: :schema_artifacts
        )
      end
      let(:indexer) { Indexer.new(indexer: base_indexer) }
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
        parsed_yaml = {"some" => "config"}
        allow(ElasticGraph::Indexer).to receive(:from_parsed_yaml).and_return(base_indexer)

        result = Indexer.from_parsed_yaml(parsed_yaml)

        expect(result.indexer).to be(base_indexer)
        expect(ElasticGraph::Indexer).to have_received(:from_parsed_yaml).with(parsed_yaml)
      end

      it "exposes the format-neutral indexer dependencies" do
        expect_to_return_non_nil_values_from_all_attributes(indexer)
      end

      it "decodes and processes a JSON Lines payload" do
        indexer.process(payload, refresh_indices: true)

        expect(processor).to have_received(:process).with(events, refresh_indices: true)
      end

      it "decodes and processes a JSON Lines payload while returning failures" do
        failure = instance_double(ElasticGraph::Indexer::FailedEventError)
        allow(processor).to receive(:process_returning_failures).and_return([failure])

        expect(indexer.process_returning_failures(payload)).to contain_exactly(failure)
        expect(processor).to have_received(:process_returning_failures).with(events, refresh_indices: false)
      end

      it "can decode a payload without processing it" do
        expect(indexer.decode(payload)).to eq(events)
        expect(processor).not_to have_received(:process)
      end
    end
  end
end
