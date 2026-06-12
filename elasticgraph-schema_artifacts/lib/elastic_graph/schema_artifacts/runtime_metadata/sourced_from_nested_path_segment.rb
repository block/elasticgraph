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
          if hash.key?(ListPathSegment::SOURCE_FIELD)
            ListPathSegment.from_hash(hash)
          else
            ObjectPathSegment.from_hash(hash)
          end
        end
      end

      # Represents a segment in a nested sourced path that navigates into a list field,
      # matching an element by its `id` against the value at `source_field`. The match is
      # always on `id` (relationships join on `id` via foreign keys), so it's implicit rather
      # than stored here.
      #
      # @private
      class ListPathSegment < ::Data.define(:field, :source_field)
        FIELD = "field"
        SOURCE_FIELD = "source_field"

        def to_dumpable_hash
          # Keys here are ordered alphabetically; please keep them that way
          {FIELD => field, SOURCE_FIELD => source_field}
        end

        def self.from_hash(hash)
          new(field: hash[FIELD], source_field: hash[SOURCE_FIELD])
        end

        # The painless script expects camelCase and discriminates list segments by the presence of `sourceField`.
        def to_painless_hash
          {"field" => field, "sourceField" => source_field}
        end
      end

      # Represents a segment in a nested sourced path that navigates into an object field.
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

        # No `sourceField`, which is how the painless script tells object segments from list segments.
        def to_painless_hash
          {"field" => field}
        end
      end
    end
  end
end
