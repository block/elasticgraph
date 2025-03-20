# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/schema_definition/mixins/verifies_graphql_name"
require "elastic_graph/support/graphql_formatter"

module ElasticGraph
  module SchemaDefinition
    module SchemaElements
      # Represents a [GraphQL directive](https://spec.graphql.org/October2021/#sec-Language.Directives).
      #
      # @!attribute [r] name
      #   @return [String] name of the directive
      # @!attribute [r] arguments
      #   @return [Hash<Symbol, Object>] directive arguments
      # @!parse class Directive < ::Data; end
      class Directive < ::Data.define(:name, :arguments)
        prepend Mixins::VerifiesGraphQLName

        # @return [String] GraphQL SDL form of the directive
        def to_sdl
          %(@#{name}#{Support::GraphQLFormatter.format_args(**arguments)})
        end

        # Duplicates this directive on another GraphQL schema element.
        #
        # @param element [Argument, EnumType, EnumValue, Field, ScalarType, TypeWithSubfields, UnionType] schema element
        # @return [void]
        def duplicate_on(element)
          element.directive name, arguments
        end
      end
    end
  end
end
