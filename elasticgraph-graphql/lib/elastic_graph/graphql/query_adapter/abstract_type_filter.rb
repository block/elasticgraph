# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  class GraphQL
    class QueryAdapter
      # Query adapter that injects a `__typename` filter when querying an abstract type (interface
      # or union) that shares an index with types that fall outside the set of its subtypes. Without
      # this filter, documents belonging to those other types would incorrectly appear in results.
      #
      # For example, if `Store` and `ThirdPartyWholesale` both share the `distribution_channels`
      # index, a query for `stores` must filter to only return documents whose `__typename` is one
      # of `Store`'s concrete subtypes.
      #
      # Subtypes with a dedicated index will not have `__typename` in their documents — the index
      # itself identifies the type — so `nil` is included to allow those documents through.
      class AbstractTypeFilter
        def call(field:, query:, args:, lookahead:, context:)
          type = field.type.unwrap_fully
          return query unless type.abstract?

          return query unless type.non_subtypes_in_shared_index.any?

          subtypes = type.subtypes # Note: subtypes returns all concrete subtypes at any depth
          query.merge_with(internal_filters: [{
            "__typename" => {query.schema_element_names.equal_to_any_of => [nil] + subtypes.map(&:name)}
          }])
        end
      end
    end
  end
end
