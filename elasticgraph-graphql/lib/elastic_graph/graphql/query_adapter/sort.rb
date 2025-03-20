# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  class GraphQL
    class QueryAdapter
      # Note: This class is not tested directly but indirectly through specs on `QueryAdapter`
      Sort = Data.define(:order_by_arg_name) do
        # @implements Sort
        def call(query:, args:, field:, lookahead:, context:)
          sort_clauses = field.sort_clauses_for(args[order_by_arg_name])

          if sort_clauses.empty?
            # When there are multiple search index definitions, we just need to pick one as the
            # source of the default sort clauses. It doesn't really matter which (if the client
            # really cared, they would have provided an `order_by` argument...) but we want our
            # logic to be consistent and deterministic, so we just use the alphabetically first
            # index here.
            sort_clauses = (_ = query.search_index_definitions.min_by(&:name)).default_sort_clauses
          end

          query.merge_with(sort: sort_clauses)
        end
      end
    end
  end
end
