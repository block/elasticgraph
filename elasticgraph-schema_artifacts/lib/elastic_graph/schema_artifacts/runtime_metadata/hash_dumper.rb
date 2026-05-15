# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  module SchemaArtifacts
    module RuntimeMetadata
      # @private
      module HashDumper
        # @param hash [Hash{String => Object}] hash to dump in sorted order
        # @yield [value] transforms each value for dumping
        def self.dump_hash(hash)
          hash.sort_by(&:first).to_h do |key, value|
            [key, yield(value)]
          end
        end
      end
    end
  end
end
