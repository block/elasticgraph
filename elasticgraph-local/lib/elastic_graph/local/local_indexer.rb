# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/indexer"
require "elastic_graph/local/indexing_coordinator"

module ElasticGraph
  module Local
    # @private
    class LocalIndexer
      def initialize(local_config_yaml, fake_data_batch_generator, output:)
        @local_indexer = ElasticGraph::Indexer.from_yaml_file(local_config_yaml)
        @indexing_coordinator = IndexingCoordinator.new(fake_data_batch_generator, output: output) do |batch|
          @local_indexer.processor.process(batch)
        end
      end

      def index_fake_data(num_batches)
        @indexing_coordinator.index_fake_data(num_batches)
      end
    end
  end
end
