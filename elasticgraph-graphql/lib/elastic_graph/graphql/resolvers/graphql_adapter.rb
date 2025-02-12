# Copyright 2024 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  class GraphQL
    module Resolvers
      # Adapts the GraphQL gem's resolver interface to the interface implemented by
      # our resolvers. Responsible for routing a resolution request to the appropriate
      # resolver.
      class GraphQLAdapter
        def initialize(schema:, runtime_metadata:, named_resolvers:)
          @schema = schema
          @named_resolvers = named_resolvers

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

          resolver = @named_resolvers.fetch(schema_field.resolver) do
            raise "No resolver yet implemented for `#{parent_type.graphql_name}.#{field.name}`."
          end

          resolver.call(parent_type, field, object, args, context)
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
      end
    end
  end
end
