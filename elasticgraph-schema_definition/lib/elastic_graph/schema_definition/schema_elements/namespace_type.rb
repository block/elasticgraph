# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/errors"
require "elastic_graph/schema_definition/schema_elements/object_type"

module ElasticGraph
  module SchemaDefinition
    module SchemaElements
      # {include:API#namespace_type}
      #
      # A namespace type is an {ObjectType} that exists purely to group fields on `Query` (or on
      # another namespace type) under a shared path. It cannot be indexed, and any no-argument field
      # (on any parent type) whose return type is a namespace type is auto-wired to the built-in
      # `:constant_value` resolver.
      #
      # @example Define a namespace type
      #   ElasticGraph.define_schema do |schema|
      #     schema.namespace_type "OlapQuery" do |t|
      #       # in the block, `t` is a NamespaceType
      #     end
      #   end
      class NamespaceType < ObjectType
        # @private
        def initialize(schema_def_state, name)
          super(schema_def_state, name) do |type|
            # Namespace types exist only in the GraphQL schema; they have no backing data to index,
            # so they are marked `graphql_only` to be excluded from indexing artifacts.
            type.graphql_only true
            # Namespace types have no backing data, so no default resolver applies. Each field either
            # sets its own or is auto-wired to `:constant_value` when its return type is another
            # namespace (handled at runtime metadata time by `HasIndices#runtime_metadata_graphql_fields_by_name`).
            type.resolve_fields_with nil
            yield type if block_given?
          end
        end

        # @return [Boolean] always `true` for a namespace type.
        def namespace?
          true
        end

        # Namespace types cannot be indexed.
        # @raise [Errors::SchemaError] always
        # @private
        def index(name, **settings, &block)
          raise Errors::SchemaError, "`#{self.name}` cannot be both an indexed type and a namespace type."
        end
      end
    end
  end
end
