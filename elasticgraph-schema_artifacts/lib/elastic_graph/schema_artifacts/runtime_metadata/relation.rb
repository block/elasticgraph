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
      class Relation < ::Data.define(:foreign_key, :direction, :references, :additional_filter, :foreign_key_nested_paths)
        FOREIGN_KEY = "foreign_key"
        DIRECTION = "direction"
        REFERENCES = "references"
        ADDITIONAL_FILTER = "additional_filter"
        FOREIGN_KEY_NESTED_PATHS = "foreign_key_nested_paths"

        def self.from_hash(hash)
          new(
            foreign_key: hash[FOREIGN_KEY],
            direction: hash.fetch(DIRECTION).to_sym,
            references: hash[REFERENCES] || "id", # TODO: Do we need this for backwards compatibility? Or do users always re-dump artifacts when they update?
            additional_filter: hash[ADDITIONAL_FILTER] || {},
            foreign_key_nested_paths: hash[FOREIGN_KEY_NESTED_PATHS] || []
          )
        end

        def to_dumpable_hash
          {
            # Keys here are ordered alphabetically; please keep them that way.
            ADDITIONAL_FILTER => additional_filter,
            DIRECTION => direction.to_s,
            FOREIGN_KEY => foreign_key,
            FOREIGN_KEY_NESTED_PATHS => foreign_key_nested_paths,
            REFERENCES => references
          }
        end
      end
    end
  end
end
