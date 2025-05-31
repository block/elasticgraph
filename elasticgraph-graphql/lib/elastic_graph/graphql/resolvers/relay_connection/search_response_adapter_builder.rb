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
          def self.build_from(schema:, search_response:, query:)
            document_paginator = query.document_paginator

            GenericAdapter.new(
              schema: schema,
              raw_nodes: search_response.to_a,
              paginator: document_paginator.paginator,
              get_total_edge_count: -> { search_response.total_document_count },
              edge_class: DocumentEdge,
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

        class DocumentEdge < GenericAdapter::Edge
          def all_highlights
            @all_highlights ||= begin
              document_type = schema.document_type_stored_in(node.index_definition_name)

              node.highlights.filter_map do |path_string, snippets|
                if (path = path_from(path_string, document_type))
                  SearchHighlight.new(schema, path, snippets)
                end
              end.sort_by(&:path)
            end
          end

          private

          def path_from(path_string, document_type)
            type = document_type

            # The GraphQL field name and `name_in_index` can be different. The datastore returns path segments using
            # the `name_in_index` but we want to return the GraphQL field name, so here we translate.
            path_string.split(".").map do |name_in_index|
              fields = type.fields_by_name_in_index[name_in_index] || []

              # It's possible (but pretty rare) for a single `name_in_index` to map to multiple GraphQL fields.
              # We don't really have a basis for preferring one over another so we just use the first one here.
              field = fields.first

              # It's possible (but should be *very* rare) that `name_in_index` does not map to any GraphQL fields.
              # Here's a situation where that could happen:
              #
              # * The schema has an `indexing_only: true` field.
              # * A custom query interceptor (used via `elasticgraph-query_interceptor`) merges some `client_filters` into an intercepted
              #   query which filters on the indexing-only field.
              #
              # It would be more correct for the query interceptor to use `internal_filters` for that case, but in case we've
              # run into this situation, logging a warning and hiding the highlight is the best we can do.
              unless field
                schema.logger.warn(
                  "Skipping SearchHighlight for #{document_type.name} #{node.id} which contains a path (#{path_string}) " \
                  "that does not map to any GraphQL field path."
                )

                return nil
              end

              type = field.type
              field.name
            end
          end
        end

        class SearchHighlight < ResolvableValue.new(:path, :snippets)
          # @dynamic initialize, path, snippets
        end
      end
    end
  end
end
