# Copyright 2024 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphql/resolvers/query_adapter"

module ElasticGraph
  class GraphQL
    module Resolvers
      # Adapts the GraphQL gem's resolver interface to the interface implemented by
      # our resolvers. Responsible for routing a resolution request to the appropriate
      # resolver.
      class GraphQLAdapter
        def initialize(schema:, datastore_query_builder:, datastore_query_adapters:, runtime_metadata:, named_resolvers:, resolvers:)
          @schema = schema
          @query_adapter = QueryAdapter.new(
            datastore_query_builder: datastore_query_builder,
            datastore_query_adapters: datastore_query_adapters
          )

          @named_resolvers = named_resolvers
          @resolvers = resolvers

          scalar_types_by_name = runtime_metadata.scalar_types_by_name
          @coercion_adapters_by_scalar_type_name = ::Hash.new do |hash, name|
            scalar_types_by_name.fetch(name).load_coercion_adapter.extension_class
          end
        end

        # To be a valid resolver, we must implement `call`, accepting the 5 arguments listed here.
        #
        # See https://graphql-ruby.org/api-doc/1.9.6/GraphQL/Schema.html#from_definition-class_method
        # (specifically, the `default_resolve` argument) for the API documentation.
        def call(parent_type, field, object, args, context)
          schema_field = @schema.field_named(parent_type.graphql_name, field.name)

          # Extract the `:lookahead` extra that we have configured all fields to provide.
          # See https://graphql-ruby.org/api-doc/1.10.8/GraphQL/Execution/Lookahead.html for more info.
          # It is not a "real" arg in the schema and breaks `args_to_schema_form` when we call that
          # so we need to peel it off here.
          lookahead = args[:lookahead]
          # Convert args to the form they were defined in the schema, undoing the normalization
          # the GraphQL gem does to convert them to Ruby keyword args form.
          args = schema_field.args_to_schema_form(args.except(:lookahead))

          resolver = resolver_for(schema_field, object) do
            raise <<~ERROR
              No resolver yet implemented for this case.

              parent_type: #{schema_field.parent_type}

              field: #{schema_field}

              obj: #{object.inspect}

              args: #{args.inspect}

              ctx: #{context.inspect}
            ERROR
          end

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

        # In order to support unions and interfaces, we must implement `resolve_type`.
        def resolve_type(supertype, object, context)
          # If `__typename` is available, use that to resolve. It should be available on any embedded abstract types...
          # (See `Inventor` in `config/schema.graphql` for an example of this kind of type union.)
          if (typename = object["__typename"])
            @schema.graphql_schema.possible_types(supertype).find { |t| t.graphql_name == typename }
          else
            # ...otherwise infer the type based on what index the object came from. This is the case
            # with unions/interfaces of individually indexed types.
            # (See `Part` in `config/schema/widgets.rb` for an example of this kind of type union.)
            @schema.document_type_stored_in(object.index_definition_name).graphql_type
          end
        end

        def coerce_input(type, value, ctx)
          scalar_coercion_adapter_for(type).coerce_input(value, ctx)
        end

        def coerce_result(type, value, ctx)
          scalar_coercion_adapter_for(type).coerce_result(value, ctx)
        end

        private

        def scalar_coercion_adapter_for(type)
          @coercion_adapters_by_scalar_type_name[type.graphql_name]
        end

        def resolver_for(field, object)
          if (resolver_name = field.resolver)
            return @named_resolvers.fetch(resolver_name)
          end

          resolver = @resolvers.find { |r| r.can_resolve?(field: field, object: object) }
          resolver || yield
        end
      end
    end
  end
end
