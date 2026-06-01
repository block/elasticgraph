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
      # Represents a segment in a nested sourced path that navigates into a list field,
      # matching an element by a key field.
      #
      # @private
      class ListPathSegment < ::Data.define(:field, :match_field, :source_field)
        # @dynamic to_painless_param
        TYPE = "list"
        FIELD = "field"
        MATCH_FIELD = "matchField"
        SOURCE_FIELD = "sourceField"

        def to_dumpable_hash
          {"type" => TYPE, FIELD => field, MATCH_FIELD => match_field, SOURCE_FIELD => source_field}
        end

        alias_method :to_painless_param, :to_dumpable_hash

        def self.from_hash(hash)
          new(field: hash[FIELD], match_field: hash[MATCH_FIELD], source_field: hash[SOURCE_FIELD])
        end
      end

      # Represents a segment in a nested sourced path that navigates into an object field.
      #
      # @private
      class ObjectPathSegment < ::Data.define(:field)
        # @dynamic to_painless_param
        TYPE = "object"
        FIELD = "field"

        def to_dumpable_hash
          {"type" => TYPE, FIELD => field}
        end

        alias_method :to_painless_param, :to_dumpable_hash

        def self.from_hash(hash)
          new(field: hash[FIELD])
        end
      end

      # @private
      module NestedSourcedPathSegment
        def self.from_hash(hash)
          case hash["type"]
          when ListPathSegment::TYPE
            ListPathSegment.from_hash(hash)
          when ObjectPathSegment::TYPE
            ObjectPathSegment.from_hash(hash)
          end
        end
      end
    end
  end
end
