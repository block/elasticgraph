# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/errors"
require "graphql"

module ElasticGraph
  class GraphQL
    class DatastoreQuery
      # Contains query logic related to pagination. Mostly delegates to `Paginator`, which
      # contains most of the logic. This merely adapts the `Paginator` to the needs of document
      # pagination. (Paginator also supports aggregation bucket pagination.)
      class DocumentPaginator < Support::MemoizableData.define(
        :sort_clauses, :paginator, :decoded_cursor_factory, :schema_element_names,
        # `individual_docs_needed`: when false, we request a `size` of 0. Set to `true` when the client is
        # requesting any document fields, or if we need documents to compute any parts of the `PageInfo`.
        :individual_docs_needed,
        # `total_document_count_needed`: when false, `track_total_hits` will be 0 in our datastore query.
        # This will prevent the datastore from doing extra work to get an accurate count
        :total_document_count_needed
      )
        # Builds a hash containing the portions of a datastore search body related to pagination.
        def to_datastore_body
          {
            size: effective_size,
            sort: effective_sort,
            search_after: search_after,
            track_total_hits: total_document_count_needed
          }.reject { |key, value| Array(value).empty? }
        end

        def sort
          @sort ||= sort_clauses.map do |clause|
            clause.transform_values do |options|
              # As per the Elasticsearch docs[^1] missing/null values get sorted last by default, but we can control
              # it here. We want to control it here to make our sorting behavior more consistent in a couple ways:
              #
              # 1. We want _document_ sorting and _aggregation_ sorting to behave the same. Aggregation sorting puts
              #    missing value buckets first when sorting ascending and last when sorting descending[^2]. Note that in
              #    Elasticsearch 7.16[^3] and above, you can control if missing buckets go first or last, but below that
              #    version you have no control. Here we match that behavior.
              # 2. Clients are likely to expect that descending sorting will produce a list in reverse order from what
              #    ascending sorting produces, but with the default behavior (missing/null values get sorted last), this
              #    is not the case. We have to use the opposite `missing` option when the `order` is the opposite.
              #
              # [^1]: https://www.elastic.co/guide/en/elasticsearch/reference/7.10/sort-search-results.html#_missing_values
              # [^2]: https://www.elastic.co/guide/en/elasticsearch/reference/7.10/search-aggregations-bucket-composite-aggregation.html#_missing_bucket
              # [^3]: https://www.elastic.co/guide/en/elasticsearch/reference/7.16/search-aggregations-bucket-composite-aggregation.html#_missing_bucket
              missing = (options.fetch("order") == "asc") ? "_first" : "_last"
              options.merge({"missing" => missing})
            end
          end
        end

        private

        def effective_size
          individual_docs_needed ? paginator.requested_page_size : 0
        end

        def effective_sort
          return [] unless effective_size > 0
          paginator.search_in_reverse? ? reverse_sort : sort
        end

        DIRECTION_OPPOSITES = {"asc" => "desc", "desc" => "asc"}.freeze
        MISSING_OPPOSITES = {"_first" => "_last", "_last" => "_first"}.freeze

        def reverse_sort
          @reverse_sort ||= sort.map do |sort_clause|
            sort_clause.transform_values do |options|
              {
                "order" => DIRECTION_OPPOSITES.fetch(options.fetch("order")),
                "missing" => MISSING_OPPOSITES.fetch(options.fetch("missing"))
              }
            end
          end
        end

        def search_after
          paginator.search_after&.then do |cursor|
            decoded_cursor_factory.sort_fields.map do |field|
              cursor.sort_values.fetch(field) do
                raise ::GraphQL::ExecutionError, "`#{cursor.encode}` is not a valid cursor for the current `#{schema_element_names.order_by}` argument."
              end
            end
          end
        end
      end

      # `Query::DocumentPaginator` exists only for use by `Query` and is effectively private.
      private_constant :DocumentPaginator
    end
  end
end
