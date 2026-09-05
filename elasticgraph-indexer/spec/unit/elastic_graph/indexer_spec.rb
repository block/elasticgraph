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
      indexer = build_indexer(indexing_event_decoder: {
        "name" => "ExampleIndexingEventDecoder",
        "require_path" => "support/example_extensions/indexing_event_decoder"
      })

      expect_to_return_non_nil_values_from_all_attributes(indexer)
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

    describe "#operation_factory" do
      it "raises a clear error when no ingestion adapters are available (e.g. for a schema defined without an ingestion format extension)" do
        indexer = build_indexer(schema_definition: lambda do |schema|
          schema.object_type "Widget" do |t|
            t.field "id", "ID!"
            t.index "widgets"
          end
        end)

        expect {
          indexer.operation_factory
        }.to raise_error Errors::ConfigError, a_string_including("No ingestion adapters are available")
      end
    end

    context "when `config.extension_modules` or runtime metadata indexer extension modules are configured" do
      it "applies the extensions when the Indexer instance is instantiated without impacting any other instances" do
        config_extension_module = Module.new do
          def datastore_router
            :config_router
          end
        end
        stub_const("IndexerConfigExtensionModule", config_extension_module)

        runtime_metadata_extension_module = Module.new do
          def monotonic_clock
            :runtime_metadata_clock
          end
        end
        stub_const("IndexerRuntimeMetadataExtensionModule", runtime_metadata_extension_module)

        extended_indexer = build_indexer(
          extension_modules: [config_extension_module],
          schema_definition: lambda do |schema|
            # `defined_at` just needs a valid require path, but needs to be outside ElasticGraph
            # to not mess with our code coverage measurement.
            schema.register_indexer_extension runtime_metadata_extension_module, defined_at: "time"
            define_schema_elements(schema)
          end
        )

        normal_indexer = build_indexer(
          schema_definition: lambda { |schema| define_schema_elements(schema) }
        )

        expect(extended_indexer.datastore_router).to eq :config_router
        expect(extended_indexer.monotonic_clock).to eq :runtime_metadata_clock

        expect(normal_indexer.datastore_router).to be_a(Indexer::DatastoreIndexingRouter)
        expect(normal_indexer.monotonic_clock).to be_a(Support::MonotonicClock)
      end

      def define_schema_elements(schema)
        schema.object_type "Widget" do |t|
          t.field "id", "ID!"
          t.index "widgets"
        end
      end
    end

    describe "#indexing_event_decoder" do
      it "builds the configured indexing event decoder" do
        indexer = build_indexer(indexing_event_decoder: {
          "name" => "ExampleIndexingEventDecoder",
          "require_path" => "support/example_extensions/indexing_event_decoder",
          "config" => {"delimiter" => "|"}
        })

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

      it "raises a clear error when no indexing event decoder is configured" do
        indexer = build_indexer

        expect {
          indexer.indexing_event_decoder
        }.to raise_error Errors::ConfigError, a_string_including("indexer.indexing_event_decoder")
      end
    end
  end
end
