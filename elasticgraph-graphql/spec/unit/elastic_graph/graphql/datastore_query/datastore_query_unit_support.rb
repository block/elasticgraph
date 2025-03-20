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

module ElasticGraph
  class GraphQL
    RSpec.shared_context "DatastoreQueryUnitSupport", :capture_logs do
      include AggregationsHelpers
      let(:graphql) { build_graphql }
      let(:builder) { graphql.datastore_query_builder }

      def datastore_body_of(query)
        query.send(:to_datastore_body).tap do |datastore_body|
          # To ensure that aggregations always satisfy the `QueryOptimizer` requirements, we validate all queries here.
          verify_aggregations_satisfy_optimizer_requirements(datastore_body[:aggs], for_query: query)
        end
      end

      def new_query(aggregations: {}, filter: nil, filters: [], **options)
        aggregations = aggregations.to_h { |agg| [agg.name, agg] } if aggregations.is_a?(::Array)

        builder.new_query(
          aggregations: aggregations,
          search_index_definitions: graphql.datastore_core.index_definitions_by_graphql_type.fetch("Widget"),
          filters: filters + [filter].compact,
          **options
        )
      end
    end
  end
end
