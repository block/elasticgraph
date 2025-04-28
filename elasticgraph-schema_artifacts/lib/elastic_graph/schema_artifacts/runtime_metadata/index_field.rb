# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/constants"

module ElasticGraph
  module SchemaArtifacts
    module RuntimeMetadata
      # Runtime metadata related to a field on a datastore index definition.
      #
      # @private
      class IndexField < ::Data.define(:source)
        SOURCE = "source"

        def self.from_hash(hash)
          new(
            source: hash[SOURCE] || SELF_RELATIONSHIP_NAME
          )
        end

        def to_dumpable_hash
          {
            # Keys here are ordered alphabetically; please keep them that way.
            SOURCE => source
          }
        end
      end
    end
  end
end
