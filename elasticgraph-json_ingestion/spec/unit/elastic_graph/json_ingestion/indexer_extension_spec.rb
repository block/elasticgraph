# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/json_ingestion/indexer_extension"

module ElasticGraph
  module JSONIngestion
    RSpec.describe IndexerExtension, :factories do
      it "makes the JSON ingestion adapter available to indexers built for schemas defined with JSON ingestion support, with no configuration needed" do
        indexer = build_indexer

        expect(indexer.ingestion_adapters).to contain_exactly(an_instance_of(IngestionAdapter))
        expect(indexer.ingestion_adapters).to be(indexer.ingestion_adapters), "expected the adapters to be memoized"

        result = indexer.operation_factory.build(build_upsert_event(:component))

        expect(result.failed_event_error).to be nil
        expect(result.operations).not_to be_empty
      end
    end
  end
end
