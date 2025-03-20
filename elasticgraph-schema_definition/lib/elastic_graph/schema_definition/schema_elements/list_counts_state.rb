# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/constants"

module ElasticGraph
  module SchemaDefinition
    module SchemaElements
      # @private
      class ListCountsState < ::Data.define(
        # the path from the root to the current list counts field
        :path_to_list_counts,
        # the path within the list counts field
        :path_from_list_counts
      )
        # @dynamic path_to_list_counts, path_from_list_counts, with

        def self.new_list_counts_field(at:)
          new(path_to_list_counts: at, path_from_list_counts: "")
        end

        INITIAL = new_list_counts_field(at: LIST_COUNTS_FIELD)

        def [](subpath)
          with(path_from_list_counts: "#{path_from_list_counts}#{subpath}.")
        end

        def path_to_count_subfield(subpath)
          count_subfield = (path_from_list_counts + subpath).gsub(".", LIST_COUNTS_FIELD_PATH_KEY_SEPARATOR)
          "#{path_to_list_counts}.#{count_subfield}"
        end
      end
    end
  end
end
