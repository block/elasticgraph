# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphql/resolvers/nested_relationships_source"
require "elastic_graph/graphql/resolvers/relay_connection"
require "elastic_graph/graphql/datastore_response/search_response"

module ElasticGraph
  class GraphQL
    module Resolvers
      # Responsible for loading nested relationships that are stored as separate documents
      # in the datastore. We use `QuerySource` for the datastore queries to avoid
      # the N+1 query problem (giving us one datastore query per layer of our graph).
      #
      # Most of the logic for this lives in ElasticGraph::Schema::RelationJoin.
      class NestedRelationships
        def initialize(elasticgraph_graphql:, config:)
          @schema_element_names = elasticgraph_graphql.runtime_metadata.schema_element_names
          @logger = elasticgraph_graphql.logger
          @monotonic_clock = elasticgraph_graphql.monotonic_clock
          @resolver_mode = elasticgraph_graphql.config.nested_relationship_resolver_mode
        end

        def resolve(field:, object:, args:, context:, lookahead:)
          log_warning = ->(**options) { log_field_problem_warning(field: field, **options) }
          join = field.relation_join
          id_or_ids = join.extract_id_or_ids_from(object, log_warning)
          query = yield

          response =
            case id_or_ids
            when nil, []
              join.blank_value
            else
              initial_response = try_synthesize_response_from_ids(field, id_or_ids, query) ||
                NestedRelationshipsSource.execute_one(
                  Array(id_or_ids).to_set,
                  query:, join:, context:,
                  monotonic_clock: @monotonic_clock,
                  mode: @resolver_mode
                )

              join.normalize_documents(initial_response) do |problem|
                log_warning.call(document: {"id" => id_or_ids}, problem: "got #{problem} from the datastore search query")
              end
            end

          RelayConnection.maybe_wrap(response, field: field, context: context, lookahead: lookahead, query: query)
        end

        private

        ONLY_ID = ["id"]

        # When a client requests only the `id` from a nested relationship, and we already have those ids,
        # we want to avoid querying the datastore, and synthesize a response instead.
        def try_synthesize_response_from_ids(field, id_or_ids, query)
          # This optimization can only be used on a relationship with an outbound foreign key.
          return nil if field.relation.direction == :in

          # If the client is requesting any fields besides `id`, we can't do this.
          return nil unless (query.requested_fields - ONLY_ID).empty?

          pagination = query.document_paginator.to_datastore_body
          search_after = pagination.dig(:search_after, 0)
          ids = Array(id_or_ids)

          sorted_ids =
            case pagination.dig(:sort, 0, "id", "order")
            when "asc"
              ids.sort.select { |id| search_after.nil? || id > search_after }
            when "desc"
              ids.sort.reverse.select { |id| search_after.nil? || id < search_after }
            else
              if ids.size < 2
                ids
              else
                # The client is sorting by something other than `id` and we have multiple ids.
                # We aren't able to determine the correct order for the ids, so we can't synthesize
                # a response.
                return nil
              end
            end

          DatastoreResponse::SearchResponse.synthesize_from_ids(
            query.search_index_expression,
            sorted_ids.first(pagination.fetch(:size)),
            decoded_cursor_factory: query.send(:decoded_cursor_factory)
          )
        end

        def log_field_problem_warning(field:, document:, problem:)
          id = document.fetch("id", "<no id>")
          @logger.warn "#{field.parent_type.name}(id: #{id}).#{field.name} had a problem: #{problem}"
        end
      end
    end
  end
end
