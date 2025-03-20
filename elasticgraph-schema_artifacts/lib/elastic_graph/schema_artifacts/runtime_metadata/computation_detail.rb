# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  module SchemaArtifacts
    module RuntimeMetadata
      # Details about our aggregation functions.
      class ComputationDetail < ::Data.define(:empty_bucket_value, :function)
        FUNCTION = "function"
        EMPTY_BUCKET_VALUE = "empty_bucket_value"

        def self.from_hash(hash)
          new(
            empty_bucket_value: hash[EMPTY_BUCKET_VALUE],
            function: hash.fetch(FUNCTION).to_sym
          )
        end

        def to_dumpable_hash
          {
            # Keys here are ordered alphabetically; please keep them that way.
            EMPTY_BUCKET_VALUE => empty_bucket_value,
            FUNCTION => function.to_s
          }
        end
      end
    end
  end
end
