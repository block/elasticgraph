# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/constants"
require "elastic_graph/support/hash_util"

module ElasticGraph
  module SchemaDefinition
    module Indexing
      # To support filtering on the `count` of a list field, we need to index the counts as we ingest
      # events. This is responsible for defining the mapping for the special `__counts` field in which
      # we store the list counts.
      #
      # @private
      module ListCountsMapping
        # Builds the `__counts` field mapping for the given `for_type`. Returns a new `mapping_hash` with
        # the extra `__counts` field merged into it.
        def self.merged_into(mapping_hash, for_type:)
          counts_properties = for_type.indexing_fields_by_name_in_index.values.flat_map do |field|
            field.paths_to_lists_for_count_indexing.map do |path|
              # We chose the `integer` type here because:
              #
              # - While we expect datasets with more documents than the max integer value (~2B), we don't expect
              #   individual documents to have any list fields with more elements than can fit in an integer.
              # - Using `long` would allow for much larger counts, but we don't want to take up double the
              #   storage space for this.
              #
              # Note that `new_list_filter_input_type` (in `schema_definition/factory.rb`) relies on this, and
              # has chosen to use `IntFilterInput` (rather than `JsonSafeLongFilterInput`) for filtering these count values.
              # If we change the mapping type here, we should re-evaluate the filter used there.
              [path, {"type" => "integer"}]
            end
          end.to_h

          return mapping_hash if counts_properties.empty?

          Support::HashUtil.deep_merge(mapping_hash, {
            "properties" => {
              LIST_COUNTS_FIELD => {
                "properties" => counts_properties
              }
            }
          })
        end
      end
    end
  end
end
