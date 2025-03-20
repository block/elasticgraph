# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphql/aggregation/key"
require "elastic_graph/graphql/datastore_query"
require "support/aggregations_helpers"
require "support/sort"

module ElasticGraph
  class GraphQL
    # Note: we use `:capture_logs` here so that if any warnings are logged, a test fails.
    # For example, we initially implemented aggregation `size` support in a way that
    # triggered a `null_pointer_exception` in one shard, which caused the datastore to
    # return a partial response that our router handled by logging a warning. The
    # `:capture_logs` here caused the tests to fail until we fixed that issue.
    RSpec.shared_context "DatastoreQueryIntegrationSupport", :uses_datastore, :factories, :capture_logs do
      include AggregationsHelpers
      include SortSupport

      let(:graphql) { build_graphql }

      def search_datastore(index_def_name: "widgets", aggregations: [], graphql: self.graphql, filter: nil, filters: [], **options, &before_msearch)
        index_def = graphql.datastore_core.index_definitions_by_name.fetch(index_def_name)

        query = graphql.datastore_query_builder.new_query(
          search_index_definitions: [index_def],
          requested_fields: ["id"],
          sort: index_def.default_sort_clauses,
          aggregations: aggregations.to_h { |agg| [agg.name, agg] },
          filters: filters + [filter].compact,
          **options
        )

        perform_query(graphql, query, &before_msearch)
      end

      def perform_query(graphql, query, &before_msearch)
        query = query.then(&before_msearch || :itself)

        graphql
          .datastore_search_router
          .msearch([query])
          .values
          .first
          .tap do |response|
            # To ensure that aggregations always satisfy the `QueryOptimizer` requirements, we validate all queries here.
            aggregations = response.raw_data["aggregations"]
            verify_aggregations_satisfy_optimizer_requirements(aggregations, for_query: query)
          end
      end

      def ids_of(*results)
        results.flatten.map { |r| r.fetch("id") { r.fetch(:id) } }
      end
    end
  end
end
