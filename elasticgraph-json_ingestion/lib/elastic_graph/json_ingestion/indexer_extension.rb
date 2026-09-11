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
    # Provides the default JSON adapter. Registered by {SchemaDefinition::APIExtension}.
    module IndexerExtension
      private

      def default_ingestion_adapters_by_format
        adapters = super
        return adapters if adapters.key?("json")

        adapters.merge(
          "json" => IngestionAdapter.new(schema_artifacts: schema_artifacts, logger: logger)
        )
      end
    end
  end
end
