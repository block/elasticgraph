# Copyright 2024 Block, Inc.
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
        def resolve(field:, object:, args:, context:, lookahead:)
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
