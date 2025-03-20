# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require_relative "datastore_query_integration_support"
require "elastic_graph/graphql/aggregation/resolvers/relay_connection_builder"
require "support/aggregations_helpers"

module ElasticGraph
  class GraphQL
    RSpec.shared_context "DatastoreAggregationQueryIntegrationSupport" do
      include_context "DatastoreQueryIntegrationSupport"

      include AggregationsHelpers

      def search_datastore_aggregations(aggregation_query, **options)
        connection = Aggregation::Resolvers::RelayConnectionBuilder.build_from_search_response(
          schema_element_names: graphql.runtime_metadata.schema_element_names,
          search_response: search_datastore(aggregations: [aggregation_query], **options),
          query: aggregation_query
        )

        connection.edges.map(&:node).map(&:bucket)
      end
    end
  end
end
