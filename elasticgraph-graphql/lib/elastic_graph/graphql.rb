# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/datastore_core"
require "elastic_graph/graphql/config"
require "elastic_graph/support/from_yaml_file"

module ElasticGraph
  # The main entry point for ElasticGraph GraphQL handling. Instantiate this to get access to the
  # different parts of this library.
  class GraphQL
    extend Support::FromYamlFile

    # @private
    # @dynamic config, logger, runtime_metadata, graphql_schema_string, datastore_core, clock
    attr_reader :config, :logger, :runtime_metadata, :graphql_schema_string, :datastore_core, :clock

    # @private
    # A factory method that builds a GraphQL instance from the given parsed YAML config.
    # `from_yaml_file(file_name, &block)` is also available (via `Support::FromYamlFile`).
    def self.from_parsed_yaml(parsed_yaml, &datastore_client_customization_block)
      new(
        config: GraphQL::Config.from_parsed_yaml(parsed_yaml),
        datastore_core: DatastoreCore.from_parsed_yaml(parsed_yaml, for_context: :graphql, &datastore_client_customization_block)
      )
    end

    # @private
    def initialize(
      config:,
      datastore_core:,
      graphql_adapter: nil,
      datastore_search_router: nil,
      filter_interpreter: nil,
      sub_aggregation_grouping_adapter: nil,
      monotonic_clock: nil,
      clock: ::Time
    )
      @config = config
      @datastore_core = datastore_core
      @graphql_adapter = graphql_adapter
      @datastore_search_router = datastore_search_router
      @filter_interpreter = filter_interpreter
      @sub_aggregation_grouping_adapter = sub_aggregation_grouping_adapter
      @monotonic_clock = monotonic_clock
      @clock = clock
      @logger = @datastore_core.logger
      @runtime_metadata = @datastore_core.schema_artifacts.runtime_metadata
      @graphql_schema_string = @datastore_core.schema_artifacts.graphql_schema_string

      # Apply any extension modules that have been configured.
      @config.extension_modules.each { |mod| extend mod }
      @runtime_metadata.graphql_extension_modules.each { |ext_mod| extend ext_mod.extension_class }
    end

    # @private
    def graphql_http_endpoint
      @graphql_http_endpoint ||= begin
        require "elastic_graph/graphql/http_endpoint"
        HTTPEndpoint.new(
          query_executor: graphql_query_executor,
          monotonic_clock: monotonic_clock,
          client_resolver: config.client_resolver
        )
      end
    end

    # @private
    def graphql_query_executor
      @graphql_query_executor ||= begin
        require "elastic_graph/graphql/query_executor"
        QueryExecutor.new(
          schema: schema,
          monotonic_clock: monotonic_clock,
          logger: logger,
          slow_query_threshold_ms: @config.slow_query_latency_warning_threshold_in_ms,
          datastore_search_router: datastore_search_router,
          config: config
        )
      end
    end

    # @private
    def schema
      @schema ||= begin
        require "elastic_graph/graphql/schema"
        Schema.new(
          graphql_schema_string: graphql_schema_string,
          config: config,
          runtime_metadata: runtime_metadata,
          index_definitions_by_graphql_type: @datastore_core.index_definitions_by_graphql_type,
          graphql_gem_plugins: graphql_gem_plugins,
          graphql_adapter: graphql_adapter
        )
      end
    end

    # @private
    def datastore_search_router
      @datastore_search_router ||= begin
        require "elastic_graph/graphql/datastore_search_router"
        DatastoreSearchRouter.new(
          datastore_clients_by_name: @datastore_core.clients_by_name,
          logger: logger,
          monotonic_clock: monotonic_clock,
          config: @config
        )
      end
    end

    # @private
    def datastore_query_builder
      @datastore_query_builder ||= begin
        require "elastic_graph/graphql/datastore_query"
        DatastoreQuery::Builder.new(
          filter_interpreter:,
          filter_node_interpreter:,
          runtime_metadata:,
          logger:,
          default_page_size: @config.default_page_size,
          max_page_size: @config.max_page_size
        )
      end
    end

    # @private
    def graphql_gem_plugins
      @graphql_gem_plugins ||= begin
        require "graphql"
        {
          # We depend on this to avoid N+1 calls to the datastore.
          ::GraphQL::Dataloader => {},
          # This is new in the graphql-ruby 2.4 release, and will be required in the future.
          # We pass `preload: true` because the way we handle the schema depends on it being preloaded.
          ::GraphQL::Schema::Visibility => {preload: true}
        }
      end
    end

    def graphql_adapter
      @graphql_adapter ||= begin
        require "elastic_graph/graphql/resolvers/graphql_adapter_builder"
        Resolvers::GraphQLAdapterBuilder.new(
          named_resolvers: named_graphql_resolvers,
          query_adapter: resolver_query_adapter,
          runtime_metadata: runtime_metadata
        ).build
      end
    end

    def resolver_query_adapter
      @resolver_query_adapter ||= begin
        require "elastic_graph/graphql/resolvers/query_adapter"
        Resolvers::QueryAdapter.new(
          datastore_query_builder: datastore_query_builder,
          datastore_query_adapters: datastore_query_adapters
        )
      end
    end

    # @private
    def named_graphql_resolvers
      @named_graphql_resolvers ||= runtime_metadata.graphql_resolvers_by_name.transform_values do |resolver|
        ext = resolver.load_resolver
        (_ = ext.extension_class).new(elasticgraph_graphql: self, config: ext.config)
      end
    end

    # @private
    def datastore_query_adapters
      @datastore_query_adapters ||= begin
        require "elastic_graph/graphql/aggregation/query_adapter"
        require "elastic_graph/graphql/query_adapter/filters"
        require "elastic_graph/graphql/query_adapter/pagination"
        require "elastic_graph/graphql/query_adapter/sort"
        require "elastic_graph/graphql/query_adapter/requested_fields"

        schema_element_names = runtime_metadata.schema_element_names

        [
          GraphQL::QueryAdapter::Pagination.new(schema_element_names: schema_element_names),
          GraphQL::QueryAdapter::Filters.new(
            schema_element_names: schema_element_names,
            filter_args_translator: filter_args_translator,
            filter_node_interpreter: filter_node_interpreter
          ),
          GraphQL::QueryAdapter::Sort.new(order_by_arg_name: schema_element_names.order_by),
          Aggregation::QueryAdapter::WithoutSchema.new(
            config: config,
            filter_args_translator: filter_args_translator,
            runtime_metadata: runtime_metadata,
            sub_aggregation_grouping_adapter: sub_aggregation_grouping_adapter
          ),
          GraphQL::QueryAdapter::RequestedFields::WithoutSchema.new
        ]
      end
    end

    # @private
    def filter_interpreter
      @filter_interpreter ||= begin
        require "elastic_graph/graphql/filtering/filter_interpreter"
        Filtering::FilterInterpreter.new(filter_node_interpreter: filter_node_interpreter, logger: logger)
      end
    end

    # @private
    def filter_node_interpreter
      @filter_node_interpreter ||= begin
        require "elastic_graph/graphql/filtering/filter_node_interpreter"
        Filtering::FilterNodeInterpreter.new(runtime_metadata: runtime_metadata)
      end
    end

    # @private
    def filter_args_translator
      @filter_args_translator ||= begin
        require "elastic_graph/graphql/filtering/filter_args_translator"
        Filtering::FilterArgsTranslator.new(schema_element_names: runtime_metadata.schema_element_names)
      end
    end

    # @private
    def sub_aggregation_grouping_adapter
      @sub_aggregation_grouping_adapter ||= begin
        require "elastic_graph/graphql/aggregation/non_composite_grouping_adapter"
        Aggregation::NonCompositeGroupingAdapter
      end
    end

    # @private
    def monotonic_clock
      @monotonic_clock ||= begin
        require "elastic_graph/support/monotonic_clock"
        Support::MonotonicClock.new
      end
    end

    # @private
    # Loads dependencies eagerly. In some environments (such as in an AWS Lambda) this is desirable as we to load all dependencies
    # at boot time instead of deferring dependency loading until we handle the first query. In other environments (such as tests),
    # it's nice to load dependencies when needed.
    def load_dependencies_eagerly
      require "graphql"
      ::GraphQL.eager_load!

      # run a simple GraphQL query to force load any dependencies needed to handle GraphQL queries
      graphql_query_executor.execute(EAGER_LOAD_QUERY, client: Client::ELASTICGRAPH_INTERNAL)
      graphql_http_endpoint # force load this too.
    end

    private

    EAGER_LOAD_QUERY = <<~EOS.strip
      query ElasticGraphEagerLoadBootQuery {
        __schema {
          types {
            kind
          }
        }
      }
    EOS
  end
end
