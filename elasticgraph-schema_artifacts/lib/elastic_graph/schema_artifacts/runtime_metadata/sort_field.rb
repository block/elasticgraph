# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/errors"

module ElasticGraph
  module SchemaArtifacts
    module RuntimeMetadata
      # @private
      class SortField < ::Data.define(:field_path, :direction)
        def initialize(field_path:, direction:)
          unless direction == :asc || direction == :desc
            raise Errors::SchemaError, "Sort direction `#{direction.inspect}` is invalid; it must be `:asc` or `:desc`"
          end

          super(field_path: field_path, direction: direction)
        end

        FIELD_PATH = "field_path"
        DIRECTION = "direction"

        def self.from_hash(hash)
          new(
            field_path: hash[FIELD_PATH],
            direction: hash.fetch(DIRECTION).to_sym
          )
        end

        def to_dumpable_hash
          {
            # Keys here are ordered alphabetically; please keep them that way.
            DIRECTION => direction.to_s,
            FIELD_PATH => field_path
          }
        end

        def to_query_clause
          {field_path => {"order" => direction.to_s}}
        end
      end
    end
  end
end
