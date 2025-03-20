# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/constants"

module ElasticGraph
  class GraphQL
    module Filtering
      # Tracks state related to field paths as we traverse our filtering data structure in order to translate
      # it to its Elasticsearch/OpenSearch form.
      #
      # Instances of this class are immutable--callers must use the provided APIs (`+`, `counts_path`, `nested`)
      # to get back new instances with state changes applied.
      FieldPath = ::Data.define(
        # The path from the overall document root.
        :from_root,
        # The path from the current parent document. Usually `from_parent` and `from_root` are the same,
        # but they'll be different when we encounter a list field indexed using the `nested` mapping type.
        # When we're traversing a subfield of a `nested` field, `from_root` will contain the full path from
        # the original, overall document root, while `from_parent` will contain the path from the current
        # nested document's root.
        :from_parent
      ) do
        # @implements FieldPath

        # Builds an empty instance.
        def self.empty
          new([], [])
        end

        def self.of(parts)
          new(parts, parts)
        end

        # Used when we encounter a `nested` field to restart the `from_parent` path (while preserving the `from_root` path).
        def nested
          FieldPath.new(from_root, [])
        end

        # Creates a new instance with `sub_path` appended.
        def +(other)
          FieldPath.new(from_root + [other], from_parent + [other])
        end

        # Converts the current paths to what they need to be to be able to query our hidden `__counts` field (which
        # is a map containing the counts of elements of every list field on the document). The `__counts` field
        # sits a the root of every document (for both an overall root document and a `nested` document). Here's an
        # example (which assumes `seasons` and `seasons.players` fields which are both `nested` and an `awards` field
        # which is a list of strings). Given a filter like this:
        #
        # filter: {seasons: {any_satisfy: {players: {any_satisfy: {results: {awards: {count: {gt: 1}}}}}}}}
        #
        # ...after processing the `awards` key, our `FieldPath` will be:
        #
        # FieldPath.new(["seasons", "players", "results", "awards"], ["results", "awards"])
        #
        # When we then reach the `count` sub field and `counts_path` is called on it, the following will be returned:
        #
        # FieldPath.new(["seasons", "players", LIST_COUNTS_FIELD, "results|awards"], [LIST_COUNTS_FIELD, "results|awards"])
        #
        # This gives us what we want:
        # - The path from the root is `seasons.players.__counts.results|awards`.
        # - The path from the (nested) parent is `__counts.results|awards`.
        #
        # Note that our `__counts` field is a flat map which uses `|` (the `LIST_COUNTS_FIELD_PATH_KEY_SEPARATOR` character)
        # to separate its parts (hence, it's `results|awards` instead of `results.awards`).
        def counts_path
          from_root_to_parent_of_counts_field = from_root[0...-from_parent.size] # : ::Array[::String]
          counts_sub_field = [LIST_COUNTS_FIELD, from_parent.join(LIST_COUNTS_FIELD_PATH_KEY_SEPARATOR)]

          FieldPath.new(from_root_to_parent_of_counts_field + counts_sub_field, counts_sub_field)
        end
      end
    end
  end
end
