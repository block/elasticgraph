# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/proto_ingestion/indexer_extension"
require "elastic_graph/proto_ingestion/schema_definition/api_extension"

module ElasticGraph
  module ProtoIngestion
    RSpec.describe IndexerExtension, :builds_indexer do
      # Defining the schema dominates each example's run time, and examples only read it, so we define it once.
      before(:context) do
        @schema_artifacts = generate_schema_artifacts(extension_modules: [SchemaDefinition::APIExtension]) do |schema|
          schema.object_type "Component" do |type|
            type.field "id", "ID!"
            type.index "components"
          end
        end
      end

      it "makes the protobuf ingestion adapter available to indexers built for schemas defined with protobuf ingestion support" do
        indexer = build_indexer(schema_artifacts: @schema_artifacts)

        expect(indexer.ingestion_adapters_by_format).to match("proto" => an_instance_of(IngestionAdapter))
      end

      it "memoizes the ingestion adapters" do
        indexer = build_indexer(schema_artifacts: @schema_artifacts)
        adapters = indexer.ingestion_adapters_by_format

        expect(indexer.ingestion_adapters_by_format).to be(adapters)
      end

      it "preserves adapters for other formats contributed by a configured extension" do
        custom_adapter = Object.new
        extension = Module.new do
          define_method(:ingestion_adapters_by_format) do
            super().merge("custom" => custom_adapter)
          end
        end

        indexer = build_indexer(schema_artifacts: @schema_artifacts, extension_modules: [extension])

        expect(indexer.ingestion_adapters_by_format).to match(
          "proto" => an_instance_of(IngestionAdapter),
          "custom" => custom_adapter
        )
      end
    end
  end
end
