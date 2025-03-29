# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  module Apollo
    module GraphQL
      # GraphQL resolver for the Apollo `Query._service` field.
      #
      # @private
      class ServiceFieldResolver
        def initialize(elasticgraph_graphql:, config:)
          # Nothing to initialize, but needs to be defined to satisfy the resolver interface.
        end

        def resolve(field:, object:, args:, context:)
          {"sdl" => service_sdl(context.fetch(:elastic_graph_schema).graphql_schema)}
        end

        private

        def service_sdl(graphql_schema)
          ::GraphQL::Schema::Printer.print_schema(graphql_schema)
        end
      end
    end
  end
end
