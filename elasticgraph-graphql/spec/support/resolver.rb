# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphql/query_details_tracker"
require "elastic_graph/graphql/resolvers/query_adapter"
require "elastic_graph/graphql/resolvers/query_source"
require "graphql"

module ResolverHelperMethods
  def resolve(type_name, field_name, document = nil, **options)
    field = graphql.schema.field_named(type_name, field_name)
    query_overrides = options.fetch(:query_overrides) { {} }
    args = field.args_to_schema_form(options.except(:query_overrides, :lookahead))
    lookahead = options[:lookahead] || GraphQL::Execution::Lookahead::NULL_LOOKAHEAD
    query_details_tracker = ElasticGraph::GraphQL::QueryDetailsTracker.empty

    ::GraphQL::Dataloader.with_dataloading do |dataloader|
      context = ::GraphQL::Query::Context.new(
        query: nil,
        schema: graphql.schema.graphql_schema,
        values: {
          elastic_graph_schema: graphql.schema,
          dataloader: dataloader,
          elastic_graph_query_tracker: query_details_tracker,
          datastore_search_router: graphql.datastore_search_router
        }
      )

      query = nil
      query_builder = -> {
        query ||= query_adapter
          .build_query_from(field: field, lookahead: lookahead, args: args, context: context)
          .merge_with(**query_overrides)
      }

      begin
        # In the 2.1.0 release of the GraphQL gem, `GraphQL::Pagination::Connection#initialize` expects a particular thread local[^1].
        # Here we initialize the thread local in a similar way to how the GraphQL gem does it[^2].
        #
        # [^1]: https://github.com/rmosolgo/graphql-ruby/blob/v2.1.0/lib/graphql/pagination/connection.rb#L94-L96
        # [^2]: https://github.com/rmosolgo/graphql-ruby/blob/v2.1.0/lib/graphql/execution/interpreter/runtime.rb#L935-L941
        ::Thread.current[:__graphql_runtime_info] = ::Hash.new { |h, k| h[k] = ::GraphQL::Execution::Interpreter::Runtime::CurrentState.new }

        if resolver.method(:resolve).parameters.include?([:keyreq, :lookahead])
          resolver.resolve(field: field, object: document, context: context, args: args, lookahead: lookahead, &query_builder)
        else
          resolver.resolve(field: field, object: document, context: context, args: args)
        end
      ensure
        ::Thread.current[:__graphql_runtime_info] = nil
      end
    end
  end
end

# Provides support for integration testing resolvers. It assumes:
#   - You have exposed `let(:graphql)` in your host example group.
#   - You are `describe`ing the resolver class (it uses `described_class`)
#   - All the initialization args for the resolver class are keyword args and are available off of `graphql`.
#
# The provided `resolve` method calls the resolver directly instead of going through the resolver adapter.
RSpec.shared_context "resolver support" do
  include ResolverHelperMethods

  subject(:resolver) { described_class.new(elasticgraph_graphql: graphql, config: {}) }

  let(:query_adapter) do
    ElasticGraph::GraphQL::Resolvers::QueryAdapter.new(
      datastore_query_builder: graphql.datastore_query_builder,
      datastore_query_adapters: graphql.datastore_query_adapters
    )
  end
end

RSpec.configure do |c|
  c.include_context "resolver support", :resolver
end
