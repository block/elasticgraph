# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/indexer"

module ElasticGraph
  RSpec.describe Indexer do
    it "returns non-nil values from each attribute" do
      expect_to_return_non_nil_values_from_all_attributes(build_indexer)
    end

    describe ".from_parsed_yaml" do
      it "builds an Indexer instance from the contents of a YAML settings file" do
        customization_block = lambda { |conn| }
        indexer = Indexer.from_parsed_yaml(parsed_test_settings_yaml, &customization_block)

        expect(indexer).to be_a(Indexer)
        expect(indexer.datastore_core.client_customization_block).to be(customization_block)
      end

      it "can build an instance with no `indexer` config" do
        indexer = Indexer.from_parsed_yaml(parsed_test_settings_yaml.except("indexer"))

        expect(indexer).to be_a(Indexer)
      end
    end

    describe "#indexing_event_decoder" do
      it "builds the configured indexing event decoder" do
        config = Indexer::Config.from_parsed_yaml("indexer" => {
          "indexing_event_decoder" => {
            "name" => "ExampleIndexingEventDecoder",
            "require_path" => "support/example_extensions/indexing_event_decoder",
            "config" => {"delimiter" => "|"}
          }
        })
        indexer = Indexer.new(config: config, datastore_core: build_datastore_core)

        decoder = indexer.indexing_event_decoder

        expect(decoder).to be_a(ExampleIndexingEventDecoder)
        expect(decoder.config).to eq({"delimiter" => "|"})
        expect(decoder.schema_artifacts).to be(indexer.schema_artifacts)
        expect(decoder.logger).to be(indexer.logger)
        expect(decoder.decode("one|two")).to eq([
          {"value" => "one"},
          {"value" => "two"}
        ])
      end
    end
  end
end
