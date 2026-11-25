# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  module ProtoIngestion
    # Enables protobuf ingestion for schemas using the protobuf schema definition extension.
    module IndexerExtension
      # @return [Hash<String, Indexer::IngestionAdapter::Interface>] the installed ingestion adapters
      def ingestion_adapters_by_format
        @ingestion_adapters_by_format ||= begin
          # Required lazily so files referencing `IndexerExtension.name` (such as `RuntimeMetadata::Schema`
          # and `SchemaDefinition::ResultsExtension`) do not trigger a circular require or load the indexer.
          require "elastic_graph/proto_ingestion/ingestion_adapter"
          super.merge("proto" => IngestionAdapter.new(schema_artifacts: schema_artifacts))
        end
      end
    end
  end
end
