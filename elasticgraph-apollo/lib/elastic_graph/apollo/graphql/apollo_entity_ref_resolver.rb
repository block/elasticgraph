# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphql/resolvers/relay_connection/array_adapter"

module ElasticGraph
  module Apollo
    module GraphQL
      # Namespace for resolvers which provide Apollo entity references from ids.
      #
      # @private
      module ApolloEntityRefResolver
        # GraphQL resolver for fields defined with `apollo_entity_ref_field` that are backed by a single id.
        #
        # @private
        class ForSingleId
          def initialize(elasticgraph_graphql:, config:)
            @source_id_field = config.fetch(:source_id_field)
            @exposed_id_field = config.fetch(:exposed_id_field)
          end

          def resolve(field:, object:, args:, context:)
            if (id = object.fetch(@source_id_field))
              {@exposed_id_field => id}
            end
          end
        end

        # GraphQL resolver for fields defined with `apollo_entity_ref_field` that are backed by an list of ids.
        #
        # @private
        class ForIdList
          def initialize(elasticgraph_graphql:, config:)
            @source_ids_field = config.fetch(:source_ids_field)
            @exposed_id_field = config.fetch(:exposed_id_field)
          end

          def resolve(field:, object:, args:, context:)
            object
              .fetch(@source_ids_field)
              .map { |id| {@exposed_id_field => id} }
          end
        end

        # GraphQL resolver for paginated fields defined with `apollo_entity_ref_paginated_collection_field`.
        #
        # @private
        class ForPaginatedList
          def initialize(elasticgraph_graphql:, config:)
            @for_id_list = ForIdList.new(elasticgraph_graphql:, config:)
          end

          def resolve(field:, object:, args:, context:)
            array = @for_id_list.resolve(field:, object:, args:, context:)
            ::ElasticGraph::GraphQL::Resolvers::RelayConnection::ArrayAdapter.build(array, args, context)
          end
        end
      end
    end
  end
end
