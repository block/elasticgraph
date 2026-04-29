# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphql/client"
require "elastic_graph/graphql/resolvers/query_source"

module ElasticGraph
  class GraphQL
    module Resolvers
      RSpec.describe QuerySource do
        describe ".datastore_opaque_id_parts_for" do
          it "includes the client name, extra parts, and query fingerprint" do
            client = Client.new(
              source_description: "client-description",
              name: "client-name",
              extra_opaque_id_parts: ["tenant=acme"]
            )
            graphql_query = instance_double(::GraphQL::Query, fingerprint: "GetColors/abc123")
            for_context = ::GraphQL::Query::Context.new(
              query: graphql_query,
              schema: Class.new(::GraphQL::Schema),
              values: {elastic_graph_client: client}
            )

            parts = QuerySource.send(:datastore_opaque_id_parts_for, for_context)

            expect(parts).to eq([
              "elasticgraph-graphql",
              "client=client-name",
              "tenant=acme",
              "query=GetColors/abc123"
            ])
          end
        end
      end
    end
  end
end
