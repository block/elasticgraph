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

    context "when `config.extension_modules` or runtime metadata indexer extension modules are configured" do
      it "applies the extensions when the Indexer instance is instantiated without impacting any other instances" do
        config_extension_module = Module.new do
          def datastore_router
            :config_router
          end
        end
        stub_const("ConfigExtensionModule", config_extension_module)

        runtime_metadata_extension_module = Module.new do
          def processor
            :runtime_metadata_processor
          end
        end
        stub_const("RuntimeMetadataExtensionModule", runtime_metadata_extension_module)

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
        expect(extended_indexer.processor).to eq :runtime_metadata_processor

        expect(normal_indexer.datastore_router).to be_a(Indexer::DatastoreIndexingRouter)
        expect(normal_indexer.processor).to be_a(Indexer::Processor)
      end

      def define_schema_elements(schema)
        schema.object_type "Widget" do |t|
          t.field "id", "ID!"
          t.index "widgets"
        end
      end
    end
  end
end
