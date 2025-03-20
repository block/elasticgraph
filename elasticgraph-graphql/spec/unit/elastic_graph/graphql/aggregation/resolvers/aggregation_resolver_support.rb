# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphql/aggregation/resolvers/node"
require "support/aggregations_helpers"

module ElasticGraph
  class GraphQL
    module Aggregation
      RSpec.shared_context "aggregation resolver support" do
        include AggregationsHelpers
        let(:graphql) { build_graphql }

        def resolve_target_nodes(
          inner_query,
          target_buckets: [],
          hit_count: nil,
          aggs: {"target" => {"buckets" => target_buckets}},
          path: ["data", "target", "nodes"]
        )
          allow(datastore_client).to receive(:msearch).and_return({"responses" => [datastore_response_payload_with_aggs(aggs, hit_count)]})

          response = graphql.graphql_query_executor.execute("query { #{inner_query} }")
          expect(response["errors"]).to eq([]).or eq(nil)
          response.dig(*path)
        end

        def datastore_response_payload_with_aggs(aggregations, hit_count)
          {
            "took" => 25,
            "timed_out" => false,
            "_shards" => {"total" => 30, "successful" => 30, "skipped" => 0, "failed" => 0},
            "hits" => {"total" => {"value" => hit_count, "relation" => "eq"}, "max_score" => nil, "hits" => []},
            "aggregations" => aggregations,
            "status" => 200
          }.compact
        end
      end
    end
  end
end
