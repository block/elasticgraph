# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/errors"

module ElasticGraph
  class GraphQL
    module Resolvers
      # Provides an adapter to the GraphQL gem by building a resolver implementation hash as documented here:
      #
      # https://graphql-ruby.org/schema/sdl.html
      class GraphQLAdapterBuilder
        def initialize(runtime_metadata:, named_resolvers:, query_adapter:)
          @runtime_metadata = runtime_metadata
          @named_resolvers = named_resolvers
          @query_adapter = query_adapter
        end

        def build
          scalar_type_hash
            .merge(object_type_hash)
            .merge({"resolve_type" => _ = ->(supertype, obj, ctx) { resolve_type(supertype, obj, ctx) }})
        end

        private

        def scalar_type_hash
          @runtime_metadata.scalar_types_by_name.transform_values do |scalar_type|
            adapter = (_ = scalar_type.load_coercion_adapter.extension_class) # : SchemaArtifacts::_ScalarCoercionAdapter[untyped, untyped]
            {
              "coerce_input" => ->(value, ctx) { adapter.coerce_input(value, ctx) },
              "coerce_result" => ->(value, ctx) { adapter.coerce_result(value, ctx) }
            }
          end
        end

        def object_type_hash
          @runtime_metadata.object_types_by_name.filter_map do |type_name, type|
            fields_hash = type.graphql_fields_by_name.filter_map do |field_name, field|
              if (resolver_name = field.resolver)
                resolver = @named_resolvers.fetch(resolver_name) do
                  raise Errors::SchemaError, "Resolver `#{resolver_name}` (for `#{type_name}.#{field_name}`) cannot be found."
                end

                resolver_lambda =
                  if resolver.method(:resolve).parameters.include?([:keyreq, :lookahead])
                    lambda do |object, args, context|
                      schema_field = context.fetch(:elastic_graph_schema).field_named(type_name, field_name)

                      # Extract the `:lookahead` extra that we have configured all fields to provide.
                      # See https://graphql-ruby.org/api-doc/1.10.8/GraphQL/Execution/Lookahead.html for more info.
                      # It is not a "real" arg in the schema and breaks `args_to_schema_form` when we call that
                      # so we need to peel it off here.
                      lookahead = args[:lookahead]

                      # Convert args to the form they were defined in the schema, undoing the normalization
                      # the GraphQL gem does to convert them to Ruby keyword args form.
                      args = schema_field.args_to_schema_form(args.except(:lookahead))

                      result = resolver.resolve(field: schema_field, object: object, args: args, context: context, lookahead: lookahead) do
                        @query_adapter.build_query_from(field: schema_field, args: args, lookahead: lookahead, context: context)
                      end

                      # Give the field a chance to coerce the result before returning it. Initially, this is only used to deal with
                      # enum value overrides (e.g. so that if `DayOfWeek.MONDAY` has been overridden to `DayOfWeek.MON`, we can coerce
                      # a `MONDAY` value being returned by a painless script to `MON`), but this is designed to be general purpose
                      # and we may use it for other coercions in the future.
                      #
                      # Note that coercion of scalar values is handled by the `coerce_result` callback below.
                      schema_field.coerce_result(result)
                    end
                  else
                    lambda do |object, args, context|
                      schema_field = context.fetch(:elastic_graph_schema).field_named(type_name, field_name)
                      # Convert args to the form they were defined in the schema, undoing the normalization
                      # the GraphQL gem does to convert them to Ruby keyword args form.
                      args = schema_field.args_to_schema_form(args)

                      result = resolver.resolve(field: schema_field, object: object, args: args, context: context)

                      # Give the field a chance to coerce the result before returning it. Initially, this is only used to deal with
                      # enum value overrides (e.g. so that if `DayOfWeek.MONDAY` has been overridden to `DayOfWeek.MON`, we can coerce
                      # a `MONDAY` value being returned by a painless script to `MON`), but this is designed to be general purpose
                      # and we may use it for other coercions in the future.
                      #
                      # Note that coercion of scalar values is handled by the `coerce_result` callback below.
                      schema_field.coerce_result(result)
                    end
                  end

                [field_name, resolver_lambda]
              end
            end.to_h

            unless fields_hash.empty?
              [type_name, fields_hash]
            end
          end.to_h
        end

        # In order to support unions and interfaces, we must implement `resolve_type`.
        def resolve_type(supertype, object, context)
          schema = context.fetch(:elastic_graph_schema)
          # If `__typename` is available, use that to resolve. It should be available on any embedded abstract types...
          # (See `Inventor` in `config/schema.graphql` for an example of this kind of type union.)
          if (typename = object["__typename"])
            schema
              .graphql_schema
              .possible_types(supertype, visibility_profile: VISIBILITY_PROFILE)
              .find { |t| t.graphql_name == typename }
          else
            # ...otherwise infer the type based on what index the object came from. This is the case
            # with unions/interfaces of individually indexed types.
            # (See `Part` in `config/schema/widgets.rb` for an example of this kind of type union.)
            schema.document_type_stored_in(object.index_definition_name).graphql_type
          end
        end
      end
    end
  end
end
