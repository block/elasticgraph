# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/proto_ingestion/ingestion_adapter"

module ElasticGraph
  module ProtoIngestion
    # Enables protobuf ingestion for schemas using the protobuf schema definition extension.
    module IndexerExtension
      # @return [Array<Object>] the installed ingestion adapters
      def ingestion_adapters
        @proto_ingestion_adapters ||= super + [IngestionAdapter.new(schema_artifacts: schema_artifacts, logger: logger)]
      end
    end
  end
end
