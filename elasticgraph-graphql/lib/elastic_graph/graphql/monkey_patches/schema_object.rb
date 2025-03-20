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
      # This module is designed to monkey patch `GraphQL::Schema::Object`, but to do so in a
      # conservative, safe way:
      #
      # - It defines no new methods.
      # - It delegates to the original implementation with `super` unless we are sure that a type should be hidden.
      # - It only changes the behavior for ElasticGraph schemas (as indicated by `:elastic_graph_schema` in the `context`).
      module SchemaObjectVisibilityDecorator
        def visible?(context)
          if context[:elastic_graph_schema]&.type_named(graphql_name)&.hidden_from_queries?
            context[:elastic_graph_query_tracker].record_hidden_type(graphql_name)
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
# a `visible?` class method on each of your type classes. However, because we load
# our schema from an SDL definition rather than defining classes for each schema
# type, we don't have a way to define the `visible?` on each of our type classes.
#
# So, here we solve this a slightly different way: we prepend a module onto
# the `GraphQL::Schema::Object` singleton class. This allows our module to
# act like a decorator and intercept calls to `visible?` so that it can hide
# types as needed. This works because all types must be defined as subclasses
# of `GraphQL::Schema::Object`, and in fact the GraphQL gem defined anonymous
# subclasses for each type in our SDL schema, as you can see here:
#
# https://github.com/rmosolgo/graphql-ruby/blob/v1.12.16/lib/graphql/schema/build_from_definition.rb#L312
GraphQL::Schema::Object.singleton_class.prepend ElasticGraph::GraphQL::MonkeyPatches::SchemaObjectVisibilityDecorator
