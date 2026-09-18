# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/indexer/event"
require "elastic_graph/indexer/failed_event_error"
require "elastic_graph/indexer/indexing_failures_error"
require "elastic_graph/indexer/malformed_event_error"
require "elastic_graph/json_ingestion/indexer"
require "json"

module ElasticGraph
  module JSONIngestion
    RSpec.describe Indexer, :ingests_json_data, :factories do
      let(:indexer) { Indexer.new(build_indexer) }

      it "decodes and processes a JSON Lines payload" do
        event = build_upsert_event_hash(:component, id: "json-indexer-process", name: "processed")

        indexer.process(json_lines(event), refresh_indices: true)

        expect(indexed_component_names).to include("processed")
      end

      it "tolerates integer-valued-but-float-typed version values, since JSON has no integer type" do
        # Here we use the monotonically increasing version number from `build_upsert_event_hash` but convert it to a float.
        # This is necessary to avoid confusing errors where version numbers on deleted documents "stick around" on
        # the index for some indeterminate period of time after we delete all documents.
        event = build_upsert_event_hash(:component, id: "json-indexer-float-version", name: "version_as_float")
        event = event.merge("version" => event.fetch("version").to_f)

        indexer.process(json_lines(event), refresh_indices: true)

        expect(indexed_component_names).to include("version_as_float")
      end

      it "returns individual failures instead of raising them" do
        invalid_event = build_upsert_event_hash(:component, id: "json-indexer-failure", name: 17)

        failures = indexer.process_returning_failures(indexer.decode(json_lines(invalid_event)))

        expect(failures.map(&:event)).to contain_exactly(ElasticGraph::Indexer::Event.from_validated_hash(invalid_event))
      end

      it "reports a malformed envelope alongside a record failure, while still indexing the valid events" do
        malformed_event = build_upsert_event_hash(:component, id: "json-indexer-malformed", name: "malformed").except("version")
        invalid_event = build_upsert_event_hash(:component, id: "json-indexer-invalid", name: 17)
        valid_event = build_upsert_event_hash(:component, id: "json-indexer-valid", name: "valid")

        failures = indexer.process_returning_failures(indexer.decode(json_lines(malformed_event, invalid_event, valid_event)), refresh_indices: true)

        expect(failures.map(&:class)).to contain_exactly(ElasticGraph::Indexer::FailedEventError, ElasticGraph::Indexer::MalformedEventError)
        expect(failures.map(&:message)).to contain_exactly(
          a_string_including("Component:json-indexer-invalid@v", "Malformed Component record"),
          a_string_including("Component:json-indexer-malformed@v:", "Malformed event payload", "version")
        )
        expect(indexed_component_names).to include("valid").and exclude("malformed", "invalid")
      end

      it "raises an `IndexingFailuresError` that counts every decoded event when asked to process a payload with failures" do
        malformed_event = build_upsert_event_hash(:component, id: "json-indexer-malformed", name: "malformed").except("version")
        valid_event = build_upsert_event_hash(:component, id: "json-indexer-valid", name: "valid")

        expect {
          indexer.process(json_lines(malformed_event, valid_event), refresh_indices: true)
        }.to raise_error(ElasticGraph::Indexer::IndexingFailuresError, a_string_including("Got 1 failure(s) from 2 event(s)", "Malformed event payload"))
      end

      def json_lines(*events)
        events.map { |event| ::JSON.generate(event) }.join("\n")
      end

      def indexed_component_names
        response = main_datastore_client.msearch(body: [{index: "components"}, {}]).dig("responses", 0)
        response.fetch("hits").fetch("hits").map { |hit| hit.dig("_source", "name") }
      end
    end
  end
end
