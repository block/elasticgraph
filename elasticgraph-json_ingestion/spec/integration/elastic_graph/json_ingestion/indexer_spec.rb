# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/json_ingestion/indexer"
require "json"

module ElasticGraph
  module JSONIngestion
    RSpec.describe Indexer, :ingests_json_data, :factories do
      let(:indexer) { Indexer.new(build_indexer) }

      it "decodes and processes a JSON Lines payload" do
        event = build_upsert_event(:component, id: "json-indexer-process", name: "processed")

        indexer.process(json_lines(event), refresh_indices: true)

        response = main_datastore_client.msearch(body: [{index: "components"}, {}]).dig("responses", 0)
        indexed_names = response.fetch("hits").fetch("hits").map { |hit| hit.dig("_source", "name") }
        expect(indexed_names).to include("processed")
      end

      it "returns individual failures instead of raising them" do
        invalid_event = build_upsert_event(:component, id: "json-indexer-failure", name: 17)

        failures = indexer.process_returning_failures(json_lines(invalid_event))

        expect(failures.map(&:event)).to contain_exactly(::ElasticGraph::Indexer::Event.from_hash(invalid_event))
      end

      def json_lines(*events)
        events.map { |event| ::JSON.generate(event) }.join("\n")
      end
    end
  end
end
