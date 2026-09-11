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
    RSpec.describe IndexerExtension, :builds_indexer, :factories do
      it "makes the JSON ingestion adapter available to indexers built for schemas defined with JSON ingestion support, with no configuration needed" do
        indexer = build_indexer

        expect(indexer.ingestion_adapters_by_format).to match("json" => an_instance_of(IngestionAdapter))
        expect(indexer.ingestion_adapters_by_format).to be(indexer.ingestion_adapters_by_format), "expected the adapters to be memoized"

        result = indexer.operation_factory.build(build_upsert_event(:component))

        expect(result.failed_event_error).to be nil
        expect(result.operations).not_to be_empty
      end

      it "preserves adapters for other formats contributed by a configured extension" do
        custom_adapter = Object.new
        extension = Module.new do
          private

          define_method(:default_ingestion_adapters_by_format) do
            super().merge("custom" => custom_adapter)
          end
        end

        indexer = build_indexer(extension_modules: [extension])

        expect(indexer.ingestion_adapters_by_format).to match(
          "json" => an_instance_of(IngestionAdapter),
          "custom" => custom_adapter
        )
      end

      it "preserves a custom JSON adapter contributed by a configured extension" do
        custom_adapter = Object.new
        extension = Module.new do
          private

          define_method(:default_ingestion_adapters_by_format) do
            super().merge("json" => custom_adapter)
          end
        end

        indexer = build_indexer(extension_modules: [extension])

        expect(indexer.ingestion_adapters_by_format).to eq("json" => custom_adapter)
      end

      it "preserves an explicitly empty ingestion adapter registry" do
        indexer = build_indexer(ingestion_adapters_by_format: {})

        expect(indexer.ingestion_adapters_by_format).to eq({})
      end

      it "preserves an explicitly injected ingestion adapter registry" do
        adapters = {"custom" => Object.new}
        indexer = build_indexer(ingestion_adapters_by_format: adapters)

        expect(indexer.ingestion_adapters_by_format).to be(adapters)
      end
    end
  end
end
