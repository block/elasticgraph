# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "graphql"
require "elastic_graph/constants"
require "elastic_graph/errors"
require "elastic_graph/graphql/schema/base_classes"
require "elastic_graph/graphql/schema/field"
require "elastic_graph/graphql/schema/type"

module ElasticGraph
  # Wraps a GraphQL::Schema object in order to provide higher-level, more convenient APIs
  # on top of that. The schema is assumed to be immutable, so this class memoizes many
  # computations it does, ensuring we never need to traverse the schema graph multiple times.
  class GraphQL
    class Schema
      BUILT_IN_TYPE_NAMES = (
        scalar_types = ::GraphQL::Schema::BUILT_IN_TYPES.keys # Int, ID, String, etc
        introspection_types = ::GraphQL::Schema.types.keys # __Type, __Schema, etc
        scalar_types.to_set.union(introspection_types)
      )

      attr_reader :element_names, :config, :logger, :graphql_schema, :runtime_metadata

      def initialize(
        graphql_schema_string:,
        config:,
        logger:,
        runtime_metadata:,
        datastore_search_router:,
        index_definitions_by_graphql_type:,
        graphql_gem_plugins:,
        graphql_adapter:
      )
        @element_names = runtime_metadata.schema_element_names
        @config = config
        @logger = logger
        @runtime_metadata = runtime_metadata
        @datastore_search_router = datastore_search_router

        resolvers_needing_lookahead = runtime_metadata.graphql_resolvers_by_name.filter_map do |name, resolver|
          name if resolver.needs_lookahead
        end.to_set

        @types_by_graphql_type = Hash.new do |hash, key|
          hash[key] = Type.new(
            self,
            key,
            index_definitions_by_graphql_type[key.graphql_name] || [],
            runtime_metadata.object_types_by_name[key.graphql_name],
            runtime_metadata.enum_types_by_name[key.graphql_name],
            resolvers_needing_lookahead
          )
        end

        # Note: as part of loading the schema, the GraphQL gem may use the resolver (such
        # when a directive has a custom scalar) so we must wait to instantiate the schema
        # as late as possible here. If we do this before initializing some of the instance
        # variables above we'll get `NoMethodError` on `nil`.
        @graphql_schema = ::GraphQL::Schema.from_definition(
          graphql_schema_string,
          base_types: {object: BaseObject},
          default_resolve: graphql_adapter,
          using: graphql_gem_plugins
        )

        # Pre-load all defined types so that all field extras can get configured as part
        # of loading the schema, before we execute the first query.
        @types_by_name = build_types_by_name

        log_hidden_types
      end

      def new_graphql_query(
        query_string,
        operation_name: nil,
        variables: {},
        context: {},
        document: nil,
        validate: true
      )
        ::GraphQL::Query.new(
          graphql_schema,
          query_string,
          variables: variables,
          operation_name: operation_name,
          document: document,
          validate: validate,
          context: context.merge({
            elastic_graph_schema: self,
            datastore_search_router: @datastore_search_router
          })
        )
      end

      def type_from(graphql_type)
        @types_by_graphql_type[graphql_type]
      end

      # Note: this does not support "wrapped" types (e.g. `Int!` or `[Int]` compared to `Int`),
      # as the graphql schema object does not give us an index of those by name. You can still
      # get type objects for wrapped types, but you need to get it from a field object of that
      # type.
      def type_named(type_name)
        @types_by_name.fetch(type_name)
      rescue KeyError => e
        msg = "No type named #{type_name} could be found"
        msg += "; Possible alternatives: [#{e.corrections.join(", ").delete('"')}]." if e.corrections.any?
        raise Errors::NotFoundError, msg
      end

      def document_type_stored_in(index_definition_name)
        indexed_document_types_by_index_definition_name.fetch(index_definition_name) do
          if index_definition_name.include?(ROLLOVER_INDEX_INFIX_MARKER)
            raise ArgumentError, "`#{index_definition_name}` is the name of a rollover index; pass the name of the parent index definition instead."
          else
            raise Errors::NotFoundError, "The index definition `#{index_definition_name}` does not appear to exist. Is it misspelled?"
          end
        end
      end

      def field_named(type_name, field_name)
        type_named(type_name).field_named(field_name)
      end

      def enum_value_named(type_name, enum_value_name)
        type_named(type_name).enum_value_named(enum_value_name)
      end

      # The list of user-defined types that are indexed document types. (Indexed aggregation types will not be included in this.)
      def indexed_document_types
        @indexed_document_types ||= defined_types.select(&:indexed_document?)
      end

      def defined_types
        @defined_types ||= @types_by_name.except(*BUILT_IN_TYPE_NAMES).values
      end

      def to_s
        "#<#{self.class.name} 0x#{__id__.to_s(16)} indexed_document_types=[#{indexed_document_types.map(&:name).sort.join(", ")}]>"
      end
      alias_method :inspect, :to_s

      private

      def build_types_by_name
        graphql_schema.types.transform_values do |graphql_type|
          @types_by_graphql_type[graphql_type]
        end
      end

      def indexed_document_types_by_index_definition_name
        @indexed_document_types_by_index_definition_name ||= indexed_document_types.each_with_object({}) do |type, hash|
          type.index_definitions.each do |index_def|
            if hash.key?(index_def.name)
              raise Errors::SchemaError, "DatastoreCore::IndexDefinition #{index_def.name} is used multiple times: #{type} vs #{hash[index_def.name]}"
            end

            hash[index_def.name] = type
          end
        end.freeze
      end

      def log_hidden_types
        hidden_types = @types_by_name.values.select(&:hidden_from_queries?)
        return if hidden_types.empty?

        logger.warn(
          "#{hidden_types.size} GraphQL types were hidden from the schema due to their backing indices being " \
          "inaccessible: #{hidden_types.map(&:name).sort.join(", ")}"
        )
      end
    end
  end
end
