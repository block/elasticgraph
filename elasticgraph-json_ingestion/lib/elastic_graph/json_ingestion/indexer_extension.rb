# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/json_ingestion/ingestion_adapter"

module ElasticGraph
  module JSONIngestion
    # Indexer extension module that makes the JSON {IngestionAdapter} available to the indexer.
    # {SchemaDefinition::APIExtension} registers this extension during schema definition, so any
    # schema defined with JSON ingestion support automatically gets JSON event ingestion at
    # indexing time--no configuration needed.
    module IndexerExtension
      # Adds the JSON {IngestionAdapter} to the indexer's available ingestion adapters.
      #
      # @return [Array<Object>] the available ingestion adapters
      def ingestion_adapters
        @ingestion_adapters ||= super + [IngestionAdapter.new(schema_artifacts: schema_artifacts, logger: logger)]
      end
    end
  end
end
