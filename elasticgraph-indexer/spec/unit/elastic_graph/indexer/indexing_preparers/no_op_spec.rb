# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/indexer/indexing_preparers/no_op"

module ElasticGraph
  class Indexer
    module IndexingPreparers
      RSpec.describe NoOp do
        it "echoes the given value back unchanged" do
          expect(NoOp.prepare_for_indexing(:anything)).to eq :anything
        end
      end
    end
  end
end
