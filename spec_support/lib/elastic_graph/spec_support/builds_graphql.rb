# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/spec_support/builds_datastore_core"
require "elastic_graph/graphql"
require "elastic_graph/graphql/config"

module ElasticGraph
  module BuildsGraphQL
    include BuildsDatastoreCore

    def build_graphql(
      extension_modules: [],
      extension_settings: {},
      slow_query_latency_warning_threshold_in_ms: 30000,
      max_page_size: 500,
      default_page_size: 50,
      datastore_core: nil,
      graphql_adapter: nil,
      monotonic_clock: nil,
      clock: ::Time,
      datastore_search_router: nil,
      filter_interpreter: nil,
      sub_aggregation_grouping_adapter: nil,
      client_resolver: nil,
      **datastore_core_options,
      &customize_datastore_config
    )
      GraphQL.new(
        datastore_core: datastore_core || build_datastore_core(for_context: :graphql, **datastore_core_options, &customize_datastore_config),
        config: GraphQL::Config.new(
          max_page_size: max_page_size,
          default_page_size: default_page_size,
          slow_query_latency_warning_threshold_in_ms: slow_query_latency_warning_threshold_in_ms,
          client_resolver: client_resolver || GraphQL::Client::DefaultResolver.new({}),
          extension_modules: extension_modules,
          extension_settings: extension_settings
        ),
        graphql_adapter: graphql_adapter,
        datastore_search_router: datastore_search_router,
        filter_interpreter: filter_interpreter,
        sub_aggregation_grouping_adapter: sub_aggregation_grouping_adapter,
        monotonic_clock: monotonic_clock,
        clock: clock
      )
    end
  end

  RSpec.configure do |c|
    c.include BuildsGraphQL, :builds_graphql
  end
end
