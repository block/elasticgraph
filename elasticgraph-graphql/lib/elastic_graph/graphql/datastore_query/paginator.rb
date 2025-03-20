# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/errors"
require "elastic_graph/support/memoizable_data"

module ElasticGraph
  class GraphQL
    class DatastoreQuery
      # A generic pagination implementation, designed to handle both document pagination and
      # aggregation pagination. Not tested directly; tests drive the `Query` interface instead.
      #
      # Our pagination support is designed to support Facebook's Relay Cursor Connections Spec.
      # The description of the pagination algorithm is directly implemented by this class:
      #
      #    https://facebook.github.io/relay/graphql/connections.htm#sec-Pagination-algorithm
      #
      # As described by the spec, we support 4 pagination arguments, and apply them in this order:
      #
      #   - `after`: items with a cursor value on or before this value are excluded
      #   - `before`: items with a cursor value on or after this value are excluded
      #   - `first`: after applying before/after, all but the first `N` items are excluded
      #   - `last`: after applying before/after/first, all but the last `N` items are excluded
      #
      # Note that `first` is applied before `last`, meaning that when both are provided (as in
      # `first: 10, last: 4`) it is interpreted as "the last 4 of the first 10". However, the Relay
      # spec itself discourages clients from passing both, but servers must still support it:
      #
      # > Including a value for both first and last is strongly discouraged, as it is likely to lead
      # > to confusing queries and results.
      #
      # For document pagination, the relay semantics are implemented on top of Elasticsearch/OpenSearch's `search_after` feature:
      #
      #    https://www.elastic.co/guide/en/elasticsearch/reference/current/search-request-search-after.html
      #
      # For aggregation pagination, the relay semantics are implemented on top of the composite aggregation
      # pagination feature:
      #
      #    https://www.elastic.co/guide/en/elasticsearch/reference/7.12/search-aggregations-bucket-composite-aggregation.html#_pagination
      #
      # In either case, the `search_after` (or `after`) argument is directly analogous to Relay's `after`.
      # To support the full Relay spec, we have to do some additional clever things:
      #
      #   - When necessary (such as for `last: 50, before: some_cursor`), we have to _reverse_ the
      #     sort, perform the query with a size of `last`, and then reverse the returned items
      #     to the originally requested order.
      #   - In some cases, we have to apply `after`, `before` or `last` as a post-processing step
      #     to the items returned by the datastore.
      #
      # Note, however, that the sort key data type used for these two cases is a bit different:
      #
      # - For document pagination, `search_after` is a list of scalar values, corresponding to the order
      #   of `sort` clauses. That is, if we are sorting on `amount` ascending and `createdAt` descending,
      #   then the `search_after` value (and the `sort` value of each document) will be an
      #   `[amount, createdAt]` tuple.
      # - For aggregation pagination, `after` (and the `key` of each aggregation bucket is an unordered
      #   hash of sort values. The sort field order is instead implied by the composite aggregation
      #   `sources`.
      class Paginator < Support::MemoizableData.define(:default_page_size, :max_page_size, :first, :after, :last, :before, :schema_element_names)
        # These methods are provided by `Data.define`:
        # @dynamic default_page_size, max_page_size, first, after, last, before, schema_element_names, initialize

        def requested_page_size
          # `+ 1` so we can tell if there are more docs for `has_next_page`/`has_previous_page`
          # ...but only if we need to get anything at all.
          (desired_page_size == 0) ? 0 : desired_page_size + 1
        end

        # Indicates if we need to search in reverse or not in order to satisfy the Relay pagination args.
        # If searching in reverse is necessary, `process_items_and_build_page_info` will take care of
        # reversing the reversed results back to their original order.
        def search_in_reverse?
          # If `first` has been provided then we _must not_ search in reverse.
          # The relay spec requires us to apply `first` before `last`, and searching
          # in reverse would prevent us from being able to return the first `N`.
          return false if first_n

          # If we do not have to return the first N results, we are free to search in
          # reverse if needed. Either `last` or `before` requires it.
          last_n || before
        end

        # The cursor values to search after (if we need to search after one at all).
        def search_after
          search_in_reverse? ? before : after
        end

        # In some cases, we're forced to search in reverse; in those caes, this is used to restore
        # the ordering of the items to the intended order.
        def restore_intended_item_order(items)
          search_in_reverse? ? items.reverse : items
        end

        # Used for post-processing a list of items from a search result, truncating the list as needed. Truncation
        # may be necessary because we may request an extra item as part of our pagination implementation.
        def truncate_items(items)
          # Remove the extra doc we requested by doing `size: size + 1`, if an extra was returned.
          # Removing the first or last doc (as this will do) will signal to `bulid_page_info`
          # that there definitely is a previous or next page.
          # Note: we use `to_a` to satisfy steep, since `Array#[]` can return `nil`--but with the arg
          # we pass, never does when items is non-empty, which our conditional enforces here.
          items = items[search_in_reverse? ? 1..-1 : 0...-1].to_a if items.size > desired_page_size

          # We can't always use `before` and `after` in the datastore query (such as when both are provided!),
          # so here we drop items from the start that come on or before `after`, and items from the
          # end that come on or after `before`.
          if (after_cursor = after)
            items = items.drop_while do |doc|
              item_sort_values_satisfy?(yield(doc, after_cursor), :<=)
            end
          end

          if (before_cursor = before)
            items = items.take_while do |doc|
              item_sort_values_satisfy?(yield(doc, before_cursor), :<)
            end
          end

          # We are not always able to use `last` as the query `size` (such as when `first` is also provided)
          # so here we apply `last`. If it has already been used this line will be a no-op.
          items = (_ = items).last(last_n.to_i) if last_n
          items
        end

        def paginated_from_singleton_cursor?
          before == DecodedCursor::SINGLETON || after == DecodedCursor::SINGLETON
        end

        def desired_page_size
          # The relay spec requires us to apply `first` before `last`, but if neither
          # is provided we fall back to `default_page_size`.
          @desired_page_size ||= [first_n || last_n || default_page_size, max_page_size].min.to_i
        end

        private

        def first_n
          @first_n ||= size_arg_value(:first, first)
        end

        def last_n
          @last_n ||= size_arg_value(:last, last)
        end

        def size_arg_value(arg_name, value)
          if value && value < 0
            raise ::GraphQL::ExecutionError, "`#{schema_element_names.public_send(arg_name)}` cannot be negative, but is #{value}."
          else
            value
          end
        end

        # A bit like `Array#<=>`, but understands ascending vs descending sorts.
        # We can't simply use doc_sort_values <=> cursor_sort_values` because our
        # sort might mix ascending and descending sorts. So, we have to go value-by-value
        # and compare each.
        def item_sort_values_satisfy?(sort_values, comparison_operator)
          if (first_unequal_sort_value = sort_values.find(&:unequal?))
            # Since each subsequent sort field is a tie breaker that only gets used if two documents
            # have the same values for all the prior sort fields, as soon as we find a sort value that
            # is unequal we can just do the comparison based on it.
            first_unequal_sort_value.item_satisfies_compared_to_cursor?(comparison_operator)
          else
            # The doc values and cursor values are all exactly equal. Return true or false on
            # the basis of whether or not the comparison operator allows exact equality.
            comparison_operator == :<= || comparison_operator == :>=
          end
        end

        SortValue = ::Data.define(:from_item, :from_cursor, :sort_direction) do
          # @implements SortValue
          def unequal?
            from_item != from_cursor
          end

          def item_satisfies_compared_to_cursor?(comparison_operator)
            if from_item.nil?
              # nil values sort first when sorting ascending, and last when sorting descending.
              # (see `DocumentPaginator#sort` for a more thorough explanation).
              sort_direction == :asc
            elsif from_cursor.nil?
              # nil values sort first when sorting ascending, and last when sorting descending.
              # (see `DocumentPaginator#sort` for a more thorough explanation).
              sort_direction == :desc
            else # both `from_item` and `from_cursor` are non-nil, and can be compared.
              result = from_item.public_send(comparison_operator, from_cursor)
              (sort_direction == :asc) ? result : !result
            end
          end
        end
      end
    end
  end
end
