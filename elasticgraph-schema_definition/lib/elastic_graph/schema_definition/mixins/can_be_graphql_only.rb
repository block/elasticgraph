# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  module SchemaDefinition
    # Namespace for modules that are used as mixins. Mixins are used to offer a consistent API for
    # schema definition features that apply to multiple types of schema elements.
    module Mixins
      # Used to indicate if a type only exists in the GraphQL schema (e.g. it has no indexing component).
      module CanBeGraphQLOnly
        # Sets whether or not this type only exists in the GraphQL schema
        #
        # @param value [Boolean] whether or not this type only exists in the GraphQL schema
        # @return [void]
        def graphql_only(value)
          @graphql_only = value
        end

        # @return [Boolean] whether or not this type only exists in the GraphQL schema
        def graphql_only?
          !!@graphql_only
        end
      end
    end
  end
end
