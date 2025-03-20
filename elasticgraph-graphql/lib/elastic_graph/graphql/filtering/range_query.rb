# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/support/hash_util"

module ElasticGraph
  class GraphQL
    module Filtering
      # Alternate `BooleanQuery` implementation for range queries. When we get a filter like this:
      #
      #     {some_field: {gt: 10, lt: 100}}
      #
      # ...we independently build a range query for each predicate. The datastore query structure would look like this:
      #
      #     {filter: [
      #       {range: {some_field: {gt: 10}}},
      #       {range: {some_field: {lt: 100}}}
      #     ]}
      #
      # However, the `range` query allows these be combined, like so:
      #
      #     {filter: [
      #       {range: {some_field: {gt: 10, lt: 100}}}
      #     ]}
      #
      # While we haven't measured it, it's likely to be more efficient (certainly not _less_ efficient!),
      # and it's essential that we combine them when we are using `any_satisfy`. Consider this filter:
      #
      #     {some_field: {any_satisfy: {gt: 10, lt: 100}}}
      #
      # This should match a document with `some_field: [5, 45, 200]` (since 45 is between 10 and 100),
      # and not match a document with `some_field: [5, 200]` (since `some_field` has no value between 10 and 100).
      # However, if we keep the range clauses separate, this document would match, because `some_field` has
      # a value > 10 and a value < 100 (even though no single value satisfies both parts!). When we combine
      # the clauses into a single `range` query then the filtering works like we expect.
      class RangeQuery < ::Data.define(:field_name, :operator, :value)
        def merge_into(bool_node)
          existing_range_index = bool_node[:filter].find_index { |clause| clause.dig(:range, field_name) }
          new_range_clause = {range: {field_name => {operator => value}}}

          if existing_range_index
            existing_range_clause = bool_node[:filter][existing_range_index]
            bool_node[:filter][existing_range_index] = Support::HashUtil.deep_merge(existing_range_clause, new_range_clause)
          else
            bool_node[:filter] << new_range_clause
          end
        end
      end
    end
  end
end
