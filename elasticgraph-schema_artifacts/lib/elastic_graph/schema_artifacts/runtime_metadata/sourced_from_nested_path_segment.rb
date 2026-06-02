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
      module SourcedFromNestedPathSegment
        def self.from_hash(hash)
          if hash.key?("match_field")
            ListPathSegment.from_hash(hash)
          else
            ObjectPathSegment.from_hash(hash)
          end
        end
      end

      # Represents a segment in a nested sourced path that navigates into a list field,
      # matching an element by a key field.
      #
      # A future PR will add `to_painless_param` to convert these segments into the
      # camelCase hash format expected by the painless script (with a "type" discriminator).
      #
      # @private
      class ListPathSegment < ::Data.define(:field, :match_field, :source_field)
        FIELD = "field"
        MATCH_FIELD = "match_field"
        SOURCE_FIELD = "source_field"

        def to_dumpable_hash
          # Keys here are ordered alphabetically; please keep them that way
          {FIELD => field, MATCH_FIELD => match_field, SOURCE_FIELD => source_field}
        end

        def self.from_hash(hash)
          new(field: hash[FIELD], match_field: hash[MATCH_FIELD], source_field: hash[SOURCE_FIELD])
        end
      end

      # Represents a segment in a nested sourced path that navigates into an object field.
      # See `ListPathSegment` for notes on `to_painless_param`.
      #
      # @private
      class ObjectPathSegment < ::Data.define(:field)
        FIELD = "field"

        def to_dumpable_hash
          # Keys here are ordered alphabetically; please keep them that way
          {FIELD => field}
        end

        def self.from_hash(hash)
          new(field: hash[FIELD])
        end
      end
    end
  end
end
