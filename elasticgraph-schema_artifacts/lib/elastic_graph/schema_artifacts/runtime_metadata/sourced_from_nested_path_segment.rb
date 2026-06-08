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
      # A future PR will add `to_painless_param` to convert these segments into the
      # camelCase hash format expected by the painless script (with a "type" discriminator).
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
