# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphql/resolvers/query_adapter"
require "rspec/expectations"

module QueryAdapterSpecSupport
  # An object that helps us test our query adapters by injecting an alternate
  # `graphql_adapter` when building the `ElasticGraph::GraphQL` instance. The
  # alternate `graphql_adapter` builds a query for each field. This is returned to
  # the caller so that it can make assertions about what GraphQL::DatastoreQuery instances get
  # built.
  #
  # Note: the `graphql_adapter` returns simple default values for each resolved field
  # (empty object, nil, etc), which means that it really only works for schemas that allow
  # all scalar fields to be nullable.
  class QueryProbe
    include ::RSpec::Matchers

    attr_reader :graphql

    def initialize(list_item_count: 1)
      @list_item_count = list_item_count
      @graphql = yield(graphql_adapter: self)

      # Only 2 resolvers yield to `Resolvers::GraphQLAdapter` to get a query built. Here we
      # put those into an array so that we can mimic the behavior in this `QueryProbe` and only
      # build an `DatastoreQuery` for the same fields.
      resolvers_module = ::ElasticGraph::GraphQL::Resolvers

      @resolvers_that_build_datastore_query = @graphql.named_graphql_resolvers.values.select do |resolver|
        case resolver
        when resolvers_module::ListRecords, resolvers_module::NestedRelationships
          true
        else
          false
        end
      end
    end

    def datastore_queries_by_field_for(query)
      @datastore_queries_by_field = ::Hash.new { |h, k| h[k] = [] }
      response = @graphql.graphql_query_executor.execute(query)
      expect(response.to_h["errors"]).to eq nil
      @datastore_queries_by_field
    end

    def errors_for(query)
      @datastore_queries_by_field = ::Hash.new { |h, k| h[k] = [] }
      response = @graphql.graphql_query_executor.execute(query)
      expect(response.to_h).to include("errors")
      response["errors"]
    end

    # Necessary for when we use `QueryProbe` on a query that requests a union or interface type.
    def resolve_type(union_type, object, context)
      # Just pick one of the possible types.
      object.fetch(:type).unwrap_fully.subtypes.first.graphql_type
    end

    def call(parent_type, field, object, args, context)
      context[:schema_element_names] = @graphql.schema.element_names
      schema_field = @graphql.schema.field_named(parent_type.graphql_name, field.name)

      lookahead = args[:lookahead]
      args = schema_field.args_to_schema_form(args.except(:lookahead))

      if resolved_with_resolver_that_builds_datastore_query?(schema_field, object)
        field_key = "#{schema_field.parent_type.name}.#{lookahead.ast_nodes.first.alias || schema_field.name}"
        @datastore_queries_by_field[field_key] << query_adapter.build_query_from(
          field: schema_field,
          args: args,
          lookahead: lookahead,
          context: context
        )
      end

      default_value_for(schema_field)
    end

    def resolved_with_resolver_that_builds_datastore_query?(schema_field, object)
      resolver = @graphql.named_graphql_resolvers.fetch(schema_field.resolver)
      @resolvers_that_build_datastore_query.include?(resolver)
    end

    def coerce_input(type, value, ctx)
      value
    end

    def coerce_result(type, value, ctx)
      value
    end

    def default_value_for(schema_field)
      object = {type: schema_field.type} # to support `#resolve_type`.

      if schema_field.type.list?
        # Return a list of one item to be the GraphQL engine tries to resolve
        # the subfields (presumably, it wouldn't attempt them if it was an empty list)
        # :nocov: (branch) -- all our tests that use this so far are for fields that wrap objects, not scalars.
        [schema_field.type.unwrap_fully.object? ? object : default_scalar_value_for(schema_field.type)] * @list_item_count
        # :nocov: (branch)
      elsif schema_field.type.object?
        object
      else
        default_scalar_value_for(schema_field.type)
      end
    end

    DEFAULT_SCALAR_VALUES = {
      "Int" => 37,
      "Float" => 37.0,
      "String" => "37",
      "ID" => "37",
      "Cursor" => "37",
      "JsonSafeLong" => 37,
      "LongString" => "37",
      "Boolean" => false,
      "Date" => "2021-08-23",
      "DateTime" => "2021-08-23T12:00:00Z",
      "DayOfWeek" => "MONDAY",
      "LocalTime" => "12:00:00"
    }

    def default_scalar_value_for(type)
      DEFAULT_SCALAR_VALUES.fetch(type.unwrap_fully.name)
    end

    def query_adapter
      @query_adapter ||= ::ElasticGraph::GraphQL::Resolvers::QueryAdapter.new(
        datastore_query_builder: graphql.datastore_query_builder,
        datastore_query_adapters: graphql.datastore_query_adapters
      )
    end
  end

  # Executes the provided `graphql_query` string against the provided schema string
  # in order to probe the execution to build a hash of { field => GraphQL::DatastoreQuery }.
  def datastore_queries_by_field_for(graphql_query, schema_artifacts:, list_item_count: 1, **graphql_opts)
    graphql_and_datastore_queries_by_field_for(
      graphql_query,
      schema_artifacts: schema_artifacts,
      list_item_count: list_item_count,
      **graphql_opts
    ).last
  end

  # Executes the provided `graphql_query` string against the provided schema string
  # in order to probe the execution to build a hash of { field => GraphQL::DatastoreQuery }.
  #
  # Returns the GraphQL instance (for things that need to work with other GraphQL dependencies) and that hash.
  def graphql_and_datastore_queries_by_field_for(graphql_query, schema_artifacts:, list_item_count: 1, **graphql_opts)
    probe = QueryProbe.new(list_item_count: list_item_count) do |graphql_adapter:|
      build_graphql(schema_artifacts: schema_artifacts, graphql_adapter: graphql_adapter, **graphql_opts)
    end

    [probe.graphql, probe.datastore_queries_by_field_for(graphql_query)]
  end

  # Executes the provided `graphql_query` string against the provided schema string
  # in order to probe the execution to get the datastore query for the schema field
  # identified by `type` and `field`.
  def datastore_query_for(schema_artifacts:, graphql_query:, type:, field:, **graphql_opts)
    queries = datastore_queries_by_field_for(graphql_query, schema_artifacts: schema_artifacts, **graphql_opts)
    field_queries = queries.fetch("#{type}.#{field}")
    expect(field_queries.size).to eq 1
    field_queries.first
  end

  def graphql_errors_for(schema_artifacts:, graphql_query:, **graphql_opts)
    QueryProbe.new do |graphql_adapter:|
      build_graphql(schema_artifacts: schema_artifacts, graphql_adapter: graphql_adapter, **graphql_opts)
    end.errors_for(graphql_query)
  end
end

RSpec.configure do |rspec|
  rspec.include QueryAdapterSpecSupport, :query_adapter
end
