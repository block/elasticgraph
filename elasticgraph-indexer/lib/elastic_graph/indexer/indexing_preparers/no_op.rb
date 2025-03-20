# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  class Indexer
    module IndexingPreparers
      class NoOp
        def self.prepare_for_indexing(value)
          value
        end
      end
    end
  end
end
