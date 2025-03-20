# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  class GraphQL
    class Schema
      # A utility module for working with GraphQL schema arguments.
      module Arguments
        # A utility method to convert the given `args_hash` to its schema form.
        # The schema form is the casing of the arguments according to the GraphQL
        # schema definition.  For example, consider a case like:
        #
        # type Query {
        #   widgets(orderBy: [WidgetSort!]): [Widget!]!
        # }
        #
        # The GraphQL gem converts all arguments to ruby keyword args style (symbolized,
        # snake_case keys) before passing the args to us, but the `orderBy` argument in
        # the schema definition uses camelCase. ElasticGraph was designed to flexibly
        # support whatever casing the schema developer chooses to use but the GraphQL
        # gem's conversion to keyword args style gets in the way. ElasticGraph needs to
        # receive the arguments in the casing form defined in the schema so that, for example,
        # when it creates a datastore query, it correctly filters on fields according
        # to the casing of the fields in the index.
        #
        # This utility method converts an args hash back to its schema form (string keys,
        # with the casing from the schema) by using the arg definitions themselves to get
        # the arg names from the GraphQL schema.
        #
        # Example:
        #
        #   to_schema_form({ order_by: ["size"] }, widgets_field)
        #     # => { "orderBy" => ["size"] }
        #
        # The implementation here was taken from a code snippet provided by the maintainer of
        # the GraphQL gem: https://github.com/rmosolgo/graphql-ruby/issues/2869
        def self.to_schema_form(args_value, args_owner)
          # For custom scalar types (such as `_Any` for apollo federation), `args_owner` won't
          # response to `arguments`.
          return args_value unless args_owner.respond_to?(:arguments)

          __skip__ = case args_value
          when Hash, ::GraphQL::Schema::InputObject
            arg_defns = args_owner.arguments.values

            {}.tap do |accumulator|
              args_value.each do |key, value|
                # Note: we could build `arg_defns` into a hash keyed by `keyword`
                # outside of this loop, to give us an O(1) lookup here. However,
                # usually there are a small number of args (e.g 1 or 2, maybe up
                # to 6 in extreme cases) so it's probably likely to be ultimately
                # slower to build the hash, particularly when you account for the
                # extra memory allocation and GC for the hash.
                arg_defn = arg_defns.find do |a|
                  a.keyword == key
                end || raise(Errors::SchemaError, "Cannot find an argument definition for #{key.inspect} on `#{args_owner.name}`")

                next_owner = arg_defn.type.unwrap
                accumulator[arg_defn.name] = to_schema_form(value, next_owner)
              end
            end
          when Array
            args_value.map { |arg_value| to_schema_form(arg_value, args_owner) }
          else
            # :nocov: -- not sure how to cover this but we want this default branch.
            args_value
            # :nocov:
          end
        end
      end
    end
  end
end
