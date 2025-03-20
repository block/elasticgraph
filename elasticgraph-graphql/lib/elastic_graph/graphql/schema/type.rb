# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/datastore_core/index_definition"
require "elastic_graph/errors"
require "elastic_graph/graphql/schema/field"
require "elastic_graph/graphql/schema/enum_value"
require "forwardable"

module ElasticGraph
  class GraphQL
    class Schema
      # Represents a GraphQL type.
      class Type
        attr_reader :graphql_type, :fields_by_name, :index_definitions, :elasticgraph_category, :graphql_only_return_type

        def initialize(
          schema,
          graphql_type,
          index_definitions,
          object_runtime_metadata,
          enum_runtime_metadata
        )
          @schema = schema
          @graphql_type = graphql_type
          @enum_values_by_name = Hash.new do |hash, key|
            hash[key] = lookup_enum_value_by_name(key)
          end

          @index_definitions = index_definitions
          @object_runtime_metadata = object_runtime_metadata
          @elasticgraph_category = object_runtime_metadata&.elasticgraph_category
          @graphql_only_return_type = object_runtime_metadata&.graphql_only_return_type
          @enum_runtime_metadata = enum_runtime_metadata
          @enum_value_names_by_original_name = (enum_runtime_metadata&.values_by_name || {}).to_h do |name, value|
            [value.alternate_original_name || name, name]
          end

          @fields_by_name = build_fields_by_name_hash(schema, graphql_type).freeze
        end

        def name
          @name ||= @graphql_type.to_type_signature
        end

        # List of index definitions that should be searched for this type.
        def search_index_definitions
          @search_index_definitions ||=
            if indexed_aggregation?
              # For an indexed aggregation, we just delegate to its source type. This works better than
              # dumping index definitions in the runtime metadata of the indexed aggregation type itself
              # because of abstract (interface/union) types. The source document type handles that (since
              # there is a supertype/subtype relationship on the document types) but that relationship
              # does not exist on the indexed aggregation.
              #
              # For example, assume we have these indexed document types:
              # - type Person {}
              # - type Company {}
              # - union Inventor = Person | Company
              #
              # We can go from `Inventor` to its subtypes to find the search indexes. However, `InventorAggregation`
              # is NOT a union of `PersonAggregation` and `CompanyAggregation`, so we can't do the same thing on the
              # indexed aggregation types. Delegating to the source type solves this case.
              @schema.type_named(@object_runtime_metadata.source_type).search_index_definitions
            else
              @index_definitions.union(subtypes.flat_map(&:search_index_definitions))
            end
        end

        # List of index definitions that should be indexed into for this type.
        # For now this is just an alias for `search_index_definitions`, but
        # in the future we expect to allow these to be different. We don't yet
        # support defining multiple indices on one GraphQL type, though, which is
        # where that would prove useful. Still, it's a useful abstraction to have
        # this method available for callers now.
        alias_method :indexing_index_definitions, :search_index_definitions

        # Unwraps the non-null type wrapping, if this type is non-null. If this type is nullable,
        # returns it as-is.
        def unwrap_non_null
          return self if nullable?
          @schema.type_from(@graphql_type.of_type)
        end

        # Fully unwraps this type, in order to extracts the underlying type (an object or scalar)
        # from its wrappings. As needed, this will unwrap any of these wrappings:
        #
        #   - non-null
        #   - list
        #   - relay connection
        def unwrap_fully
          @unwrap_fully ||= begin
            unwrapped = @schema.type_from(@graphql_type.unwrap)

            if unwrapped.relay_connection?
              unwrapped
                .field_named(@schema.element_names.edges).type.unwrap_fully
                .field_named(@schema.element_names.node).type.unwrap_fully
            else
              unwrapped
            end
          end
        end

        # Returns the subtypes of this type, if it has any. This is like `#possible_types` provided by the
        # GraphQL gem, but that includes a type itself when you ask for the possible types of a non-abstract type.
        def subtypes
          @subtypes ||= @schema.graphql_schema.possible_types(graphql_type).map { |t| @schema.type_from(t) } - [self]
        end

        def field_named(field_name)
          @fields_by_name.fetch(field_name)
        rescue KeyError => e
          msg = "No field named #{field_name} (on type #{name}) could be found"
          msg += "; Possible alternatives: [#{e.corrections.join(", ").delete('"')}]." if e.corrections.any?
          raise Errors::NotFoundError, msg
        end

        def enum_value_named(enum_value_name)
          @enum_values_by_name[enum_value_name]
        end

        def coerce_result(result)
          @enum_value_names_by_original_name.fetch(result, result)
        end

        def to_s
          "#<#{self.class.name} #{name}>"
        end
        alias_method :inspect, :to_s

        # ********************************************************************************************
        # Predicates
        #
        # Below here are a bunch of predicates that can be used to ask questions of a type. GraphQL's
        # "wrapping" type system (e.g. non-null wraps nullable; lists wrap objects or scalars) adds
        # some complexity and nuance here. We have decided to implement these predicates to auto-unwrap
        # non-null (e.g. SomeType! -> SomeType). For example, `object?` will return `true` from both a
        # nullable and non-nullable object type, because both are fundamentally objects. Importantly,
        # we do not ever auto-unwrap a type from its list or relay connection wrapping; if the caller
        # wants that, they can manually unwrap before calling the predicate.
        #
        # Note also that `non_null?` and `nullable?` are an exception: since they check nullability,
        # we do not auto-unwrap non-null on them, naturally.
        # ********************************************************************************************

        extend Forwardable
        def_delegators :@graphql_type, :list?, :non_null?

        def nullable?
          !non_null?
        end

        def abstract?
          return unwrap_non_null.abstract? if non_null?
          @graphql_type.kind.abstract?
        end

        def enum?
          return unwrap_non_null.enum? if non_null?
          @graphql_type.kind.enum?
        end

        # Returns `true` if this type serializes as a JSON object, with sub-fields.
        # Note this is slightly different from the GraphQL gem and GraphQL spec: it considers
        # inputs to be distinct from objects, but for our purposes we consider inputs to be
        # objects since they have sub-fields and serialize as JSON objects.
        def object?
          return unwrap_non_null.object? if non_null?
          kind = @graphql_type.kind
          kind.abstract? || kind.object? || kind.input_object?
        end

        # Is the type a user-defined document type directly indexed in the index?
        def indexed_document?
          return unwrap_non_null.indexed_document? if non_null?
          return false if indexed_aggregation?
          return true if subtypes.any? && subtypes.all?(&:indexed_document?)
          @index_definitions.any?
        end

        def indexed_aggregation?
          unwrapped_has_category?(:indexed_aggregation)
        end

        # Indicates if this type is an object type that is embedded in another indexed type
        # in the index mapping. Note: we have avoided the term `nested` here because it
        # is a specific Elasticsearch/OpenSearch mapping type that we will not necessarily be using:
        # https://www.elastic.co/guide/en/elasticsearch/reference/current/nested.html
        def embedded_object?
          return unwrap_non_null.embedded_object? if non_null?
          return false if relay_edge? || relay_connection? || @graphql_type.kind.input_object?
          object? && !indexed_document? && !indexed_aggregation?
        end

        def collection?
          list? || relay_connection?
        end

        def relay_connection?
          unwrapped_has_category?(:relay_connection)
        end

        def relay_edge?
          unwrapped_has_category?(:relay_edge)
        end

        # Indicates this type should be hidden in the GraphQL schema so as to not be queryable.
        # We only hide a type if both of the following are true:
        #
        # - It's backed by one or more search index definitions
        # - None of the search index definitions are accessible from queries
        def hidden_from_queries?
          return false if search_index_definitions.empty?
          search_index_definitions.none?(&:accessible_from_queries?)
        end

        private

        def lookup_enum_value_by_name(enum_value_name)
          graphql_enum_value = @graphql_type.values.fetch(enum_value_name)

          EnumValue.new(
            name: graphql_enum_value.graphql_name,
            type: self,
            runtime_metadata: @enum_runtime_metadata&.values_by_name&.dig(enum_value_name)
          )
        rescue KeyError => e
          msg = "No enum value named #{enum_value_name} (on type #{name}) could be found"
          msg += "; Possible alternatives: [#{e.corrections.join(", ").delete('"')}]." if e.corrections.any?
          raise Errors::NotFoundError, msg
        end

        def build_fields_by_name_hash(schema, graphql_type)
          fields_hash =
            if graphql_type.respond_to?(:fields)
              graphql_type.fields
            elsif graphql_type.kind.input_object?
              # Unfortunately, input objects do not have a `fields` method; instead it is called `arguments`.
              graphql_type.arguments
            else
              {}
            end

          # Eagerly fan out and instantiate all `Field` objects so that the :extras
          # get added to each field as require before we execute the first query
          fields_hash.each_with_object({}) do |(name, field), hash|
            hash[name] = Field.new(schema, self, field, @object_runtime_metadata&.graphql_fields_by_name&.dig(name))
          end
        end

        def unwrapped_has_category?(category)
          unwrap_non_null.elasticgraph_category == category
        end
      end
    end
  end
end
