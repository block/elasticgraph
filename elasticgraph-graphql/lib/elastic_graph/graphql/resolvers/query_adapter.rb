# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  class GraphQL
    module Resolvers
      # Responsible for taking raw GraphQL query arguments and transforming
      # them into a DatastoreQuery object.
      class QueryAdapter
        def initialize(datastore_query_builder:, datastore_query_adapters:)
          @datastore_query_builder = datastore_query_builder
          @datastore_query_adapters = datastore_query_adapters
        end

        def build_query_from(field:, args:, lookahead:, context:)
          monotonic_clock_deadline = context[:monotonic_clock_deadline]

          # Building an `DatastoreQuery` is not cheap; we do a lot of work to:
          #
          # 1) Convert the `args` to their schema form.
          # 2) Reduce over our different query builders into a final `Query` object
          # 3) ...and those individual query builders often do a lot of work (traversing lookaheads, etc).
          #
          # So it is beneficial to avoid re-creating the exact same `DatastoreQuery` object when
          # we are resolving the same field in the context of a different object. For example,
          # consider a query like:
          #
          # query {
          #   widgets {
          #     components {
          #       id
          #       parts {
          #         id
          #       }
          #     }
          #   }
          # }
          #
          # Here `components` and `parts` are nested relation fields. If we load 50 of each collection,
          # this `build_query_from` method will be called 50 times for the `Widget.components` field,
          # and 2500 times (50 * 50) for the `Component.parts` field...but for a given field, the
          # built `DatastoreQuery` will be exactly the same.
          #
          # Therefore, it is beneficial to memoize the `DatastoreQuery` to avoid re-doing the same work
          # over and over again, provided we can do so safely.
          #
          # `context` is a hash-like `GraphQL::Query::Context` object. Each executed query gets its own
          # instance, so we can safely cache things in it and trust that it will not "leak" to another
          # query execution. We carefully build a cache key below to ensure that we only ever reuse
          # the same `DatastoreQuery` in a situation that would produce the exact same `DatastoreQuery`.
          context[:datastore_query_cache] ||= {}
          context[:datastore_query_cache][cache_key_for(field, args, lookahead)] ||=
            build_new_query_from(field, args, lookahead, context, monotonic_clock_deadline)
        end

        private

        def build_new_query_from(field, args, lookahead, context, monotonic_clock_deadline)
          unwrapped_type = field.type.unwrap_fully

          initial_query = @datastore_query_builder.new_query(
            search_index_definitions: unwrapped_type.search_index_definitions,
            monotonic_clock_deadline: monotonic_clock_deadline
          )

          @datastore_query_adapters.reduce(initial_query) do |query, adapter|
            adapter.call(query: query, field: field, args: args, lookahead: lookahead, context: context)
          end
        end

        def cache_key_for(field, args, lookahead)
          # Unfortunately, `Lookahead` does not define `==` according to its internal state,
          # so `l1 == l2` with the same internal state returns false. So we have to pull
          # out its individual state fields in the cache key for our caching to work here.
          [field, args, lookahead.ast_nodes, lookahead.field, lookahead.owner_type]
        end
      end
    end
  end
end
