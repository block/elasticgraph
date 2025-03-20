# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/support/untyped_encoder"

module ElasticGraph
  class Indexer
    module IndexingPreparers
      class Untyped
        # Converts the given untyped value to a String so it can be indexed in a `keyword` field.
        def self.prepare_for_indexing(value)
          Support::UntypedEncoder.encode(value)
        end
      end
    end
  end
end
