# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/apollo/schema_definition/apollo_directives"

module ElasticGraph
  module Apollo
    module SchemaDefinition
      # Extends {ElasticGraph::SchemaDefinition::SchemaElements::ObjectType} to offer Apollo object type directives.
      module ObjectTypeExtension
        include ApolloDirectives::Authenticated
        include ApolloDirectives::Extends
        include ApolloDirectives::External
        include ApolloDirectives::Inaccessible
        include ApolloDirectives::InterfaceObject
        include ApolloDirectives::Key
        include ApolloDirectives::Policy
        include ApolloDirectives::RequiresScopes
        include ApolloDirectives::Shareable
        include ApolloDirectives::Tag
      end
    end
  end
end
