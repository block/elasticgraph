# Copyright 2024 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  module Apollo
    # Namespace for all Apollo GraphQL enging logic.
    #
    # @note This module provides no public types or APIs. It will be used automatically when you use
    #   {SchemaDefinition::APIExtension} as a schema definition extension module.
    module GraphQL
      # ElasticGraph application extension module designed to hook into the ElasticGraph
      # GraphQL engine in order to support Apollo-specific fields.
      #
      # @private
      module EngineExtension
        # @private
        def named_graphql_resolvers
          @named_graphql_resolvers ||= begin
            require "elastic_graph/apollo/graphql/entities_field_resolver"
            require "elastic_graph/apollo/graphql/service_field_resolver"

            apollo_entities = EntitiesFieldResolver.new(
              datastore_query_builder: datastore_query_builder,
              schema_element_names: runtime_metadata.schema_element_names
            )

            apollo_service = ServiceFieldResolver.new

            super.merge({apollo_entities: apollo_entities, apollo_service: apollo_service})
          end
        end

        # @private
        def graphql_gem_plugins
          @graphql_gem_plugins ||= begin
            require "apollo-federation/tracing/proto"
            require "apollo-federation/tracing/node_map"
            require "apollo-federation/tracing/tracer"
            require "apollo-federation/tracing"

            # @type var options: ::Hash[::Symbol, untyped]
            options = {}
            super.merge(ApolloFederation::Tracing => options)
          end
        end

        # @private
        def graphql_http_endpoint
          @graphql_http_endpoint ||= super.tap do |endpoint|
            require "elastic_graph/apollo/graphql/http_endpoint_extension"
            endpoint.extend HTTPEndpointExtension
          end
        end
      end
    end
  end
end
