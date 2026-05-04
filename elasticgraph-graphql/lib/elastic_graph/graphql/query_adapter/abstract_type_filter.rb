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
      # For example, given this hierarchy:
      #
      #   DistributionChannel (abstract interface, index: distribution_channels)
      #   ├── Wholesale            (abstract interface, distribution_channels index)
      #   │   ├── DirectWholesaler (concrete, distribution_channels index)
      #   │   └── BrokerWholesaler (concrete, distribution_channels index)
      #   └── Retail               (abstract interface, distribution_channels index)
      #       └── Store            (abstract interface, distribution_channels index)
      #           ├── OnlineStore  (concrete, distribution_channels index)
      #           └── PhysicalStore (concrete, physical_stores index — dedicated)
      #
      # A query for `retailers` (i.e. the `Retail` interface) searches both `distribution_channels`
      # and `physical_stores`. Without a `__typename` filter, `DirectWholesaler` and
      # `BrokerWholesaler` documents from `distribution_channels` would appear in results.
      # So we inject:
      #
      #   __typename: { equal_to_any_of: [nil, "OnlineStore", "PhysicalStore"] }
      #
      # `nil` is included because `PhysicalStore` has a dedicated index where documents lack
      # `__typename` — the index itself identifies the type. We only include `nil` when at least
      # one of the queried indexes stores only a single type (and thus lacks `__typename`).
      class AbstractTypeFilter
        def initialize(schema_element_names)
          @equal_to_any_of = schema_element_names.equal_to_any_of
        end

        def call(field:, query:, args:, lookahead:, context:)
          type = field.type.unwrap_fully

          # For derived types (e.g. indexed aggregations), resolve the underlying document type so we can
          # apply the same __typename scoping as we do for document queries.
          doc_type = type.source_type || type

          return query unless doc_type.shares_index_with_non_subtypes?

          schema = context.fetch(:elastic_graph_schema)
          subtypes = doc_type.subtypes # Note: subtypes returns all concrete subtypes at any depth
          typename_values = subtypes.map(&:name)
          # Only include nil when at least one queried index stores only a single type — those
          # documents lack __typename (the index itself identifies the type), so nil is needed to
          # allow them through.
          if doc_type.search_index_definitions.any? { |idx| schema.document_types_stored_in(idx.name).size == 1 }
            typename_values += [nil]
          end
          query.merge_with(internal_filters: [{
            "__typename" => {@equal_to_any_of => typename_values}
          }])
        end
      end
    end
  end
end
