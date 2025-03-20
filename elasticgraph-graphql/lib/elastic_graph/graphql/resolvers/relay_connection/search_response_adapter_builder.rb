# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphql/resolvers/relay_connection/generic_adapter"

module ElasticGraph
  class GraphQL
    module Resolvers
      module RelayConnection
        # Adapts an `DatastoreResponse::SearchResponse` to what the graphql gem expects for a relay connection.
        class SearchResponseAdapterBuilder
          def self.build_from(schema_element_names:, search_response:, query:)
            document_paginator = query.document_paginator

            GenericAdapter.new(
              schema_element_names: schema_element_names,
              raw_nodes: search_response.to_a,
              paginator: document_paginator.paginator,
              get_total_edge_count: -> { search_response.total_document_count },
              to_sort_value: ->(document, decoded_cursor) do
                (_ = document).sort.zip(decoded_cursor.sort_values.values, document_paginator.sort).map do |from_document, from_cursor, sort_clause|
                  DatastoreQuery::Paginator::SortValue.new(
                    from_item: from_document,
                    from_cursor: from_cursor,
                    sort_direction: sort_clause.values.first.fetch("order").to_sym
                  )
                end
              end
            )
          end
        end
      end
    end
  end
end
