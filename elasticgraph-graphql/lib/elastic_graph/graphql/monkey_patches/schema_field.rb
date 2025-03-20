# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "graphql"

module ElasticGraph
  class GraphQL
    module MonkeyPatches
      # This module is designed to monkey patch `GraphQL::Schema::Field`, but to do so in a
      # conservative, safe way:
      #
      # - It defines no new methods.
      # - It delegates to the original implementation with `super` unless we are sure that a type should be hidden.
      # - It only changes the behavior for ElasticGraph schemas (as indicated by `:elastic_graph_schema` in the `context`).
      module SchemaFieldVisibilityDecorator
        def visible?(context)
          # `DynamicFields` and `EntryPoints` are built-in introspection types that `field_named` below doesn't support:
          # https://github.com/rmosolgo/graphql-ruby/blob/0df187995c971b399ed7cc1fbdcbd958af6c4ade/lib/graphql/introspection/entry_points.rb
          # https://github.com/rmosolgo/graphql-ruby/blob/0df187995c971b399ed7cc1fbdcbd958af6c4ade/lib/graphql/introspection/dynamic_fields.rb
          #
          # ...so if the owner is one of those we just return `super` here.
          return super if %w[DynamicFields EntryPoints].include?(owner.graphql_name)

          if context[:elastic_graph_schema]&.field_named(owner.graphql_name, graphql_name)&.hidden_from_queries?
            return false
          end

          super
        end
      end
    end
  end
end

# As per https://graphql-ruby.org/authorization/visibility.html, the public API
# provided by the GraphQL gem to control visibility of object types is to define
# a `visible?` instance method on a custom subclass of `GraphQL::Schema::Field`.
# However, because we load our schema from an SDL definition rather than defining
# classes for each schema type, we don't have a way to register a custom subclass
# to be used for fields.
#
# So, here we solve this a slightly different way: we prepend a module onto
# the `GraphQL::Schema::Field class. This allows our module to act like a
# decorator and intercept calls to `visible?` so that it can hide types as needed.
module GraphQL
  class Schema
    class Field
      prepend ::ElasticGraph::GraphQL::MonkeyPatches::SchemaFieldVisibilityDecorator
    end
  end
end
