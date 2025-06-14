# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/errors"
require "elastic_graph/graphql/schema/relation_join"
require "elastic_graph/graphql/schema/arguments"

module ElasticGraph
  class GraphQL
    class Schema
      # Represents a field within a GraphQL type.
      class Field
        # The type in which the field resides.
        attr_reader :parent_type

        attr_reader :schema, :schema_element_names, :graphql_field, :name_in_index, :relation, :computation_detail, :resolver

        def initialize(schema, parent_type, graphql_field, runtime_metadata, resolvers_needing_lookahead)
          @schema = schema
          @schema_element_names = schema.element_names
          @parent_type = parent_type
          @graphql_field = graphql_field
          @relation = runtime_metadata&.relation
          @computation_detail = runtime_metadata&.computation_detail
          @resolver = runtime_metadata&.resolver
          @name_in_index = runtime_metadata&.name_in_index || name
          @graphql_field.extras([:lookahead]) if resolvers_needing_lookahead.include?(@resolver&.name)
        end

        def type
          @type ||= @schema.type_from(@graphql_field.type)
        end

        def name
          @name ||= @graphql_field.name
        end

        def path_in_index
          @path_in_index ||= name_in_index.split(".")
        end

        # Returns an object that knows how this field joins to its relation.
        # Used by ElasticGraph::Resolvers::NestedRelationships.
        def relation_join
          # Not every field has a join relation, so it can be nil. But we do not want
          # to re-compute that on every call, so we return @relation_join if it's already
          # defined rather than if its truthy.
          return @relation_join if defined?(@relation_join)
          @relation_join = RelationJoin.from(self)
        end

        # Given an array of sort enums, returns an array of datastore compatible sort clauses
        def sort_clauses_for(sorts)
          Array(sorts).flat_map { |sort| sort_argument_type.enum_value_named(sort).sort_clauses }
        end

        # Indicates if this is an aggregated field (used inside an `Aggregation` type).
        def aggregated?
          type.unwrap_non_null.elasticgraph_category == :scalar_aggregated_values
        end

        def args_to_schema_form(args)
          Arguments.to_schema_form(args, @graphql_field)
        end

        # Returns a list of field names that are required from the datastore in order
        # to resolve this field at GraphQL query handling time.
        def index_field_names_for_resolution
          # For an embedded object, we do not require any fields because it is the nested fields
          # that we will request from the datastore, which will be required to resolve them. But
          # we do not need to request the embedded object field itself.
          return [] if type.embedded_object?
          return [] if parent_type.relay_connection? || parent_type.relay_edge?
          return index_id_field_names_for_relation if relation_join

          [name_in_index]
        end

        # Indicates this field should be hidden in the GraphQL schema so as to not be queryable.
        # We only hide a field if resolving it would require using a datastore cluster that
        # we can't access. For the most part, this just delegates to `Type#hidden_from_queries?`
        # which does the index accessibility check.
        def hidden_from_queries?
          # The type has logic to check if the backing datastore index is accessible, so we just
          # delegate to that logic here.
          type.unwrap_fully.hidden_from_queries?
        end

        def coerce_result(result)
          return result unless parent_type.graphql_only_return_type
          type.coerce_result(result)
        end

        def description
          "#{@parent_type.name}.#{name}"
        end

        def to_s
          "#<#{self.class.name} #{description}>"
        end
        alias_method :inspect, :to_s

        private

        # Returns the `order_by` arguments type field (unwrapped)
        def sort_argument_type
          @sort_argument_type ||= begin
            graphql_argument = @graphql_field.arguments.fetch(schema_element_names.order_by) do
              raise Errors::SchemaError, "`#{schema_element_names.order_by}` argument not defined for field `#{parent_type.name}.#{name}`."
            end
            @schema.type_from(graphql_argument.type.unwrap)
          end
        end

        def index_id_field_names_for_relation
          if type.unwrap_fully == parent_type # means its a self-referential relation (e.g. child to parent of same type)
            # Since it's self-referential, the `filter_id_field` (which lives on the "remote" type) also must
            # exist as a field in our DatastoreCore::IndexDefinition.
            [relation_join.document_id_field_name, relation_join.filter_id_field_name]
          else
            [relation_join.document_id_field_name]
          end
        end
      end
    end
  end
end
