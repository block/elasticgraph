# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphql/decoded_cursor"
require "elastic_graph/graphql/datastore_query"

module ElasticGraph
  module SortSupport
    TIEBREAKER_SORT_CLAUSES = GraphQL::DatastoreQuery::TIEBREAKER_SORT_CLAUSES

    def sort_list_with_missing_option_for(*sort_clauses)
      sort_list_for(*sort_clauses).map do |clause|
        clause.transform_values do |options|
          options.merge("missing" => (options.fetch("order") == "asc") ? "_first" : "_last")
        end
      end
    end

    def sort_list_for(*sort_clauses)
      flattened_sort_clauses = sort_clauses.flatten
      # :nocov: -- currently we don't have any tests that explicitly specify `id` as the sort field, but we might in the future
      flattened_sort_clauses + ((flattened_sort_clauses.any? { |s| s.key?("id") }) ? [] : TIEBREAKER_SORT_CLAUSES)
      # :nocov:
    end

    def decoded_cursor_factory_for(*sort_clauses_or_fields)
      sort_clauses_or_fields = sort_clauses_or_fields.flatten
      if sort_clauses_or_fields.first.is_a?(Hash) # it is a list of clauses
        GraphQL::DecodedCursor::Factory.from_sort_list(sort_list_for(*sort_clauses_or_fields))
      else
        # cursor doesn't care about sort direction (asc VS desc), so we just assign `asc` as a dummy value
        decoded_cursor_factory_for(sort_clauses_or_fields.map { |field| {field => {"order" => "asc"}} })
      end
    end
  end
end
