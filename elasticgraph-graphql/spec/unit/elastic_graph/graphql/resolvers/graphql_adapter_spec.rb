# Copyright 2024 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphql/resolvers/graphql_adapter"

module ElasticGraph
  class GraphQL
    module Resolvers
      RSpec.describe GraphQLAdapter do
        let(:graphql) { build_graphql }
        let(:schema) { graphql.schema }

        it "raises a clear error when no resolver can be found" do
          adapter = GraphQLAdapter.new(
            schema: schema,
            datastore_query_builder: graphql.datastore_query_builder,
            datastore_query_adapters: graphql.datastore_query_adapters,
            runtime_metadata: graphql.runtime_metadata,
            named_resolvers: graphql.named_graphql_resolvers,
            resolvers: graphql.graphql_resolvers
          )

          expect {
            adapter.call(
              schema.type_named(:Widget).graphql_type,
              schema.field_named(:Widget, :id).instance_variable_get(:@graphql_field),
              nil,
              {},
              {}
            )
          }.to raise_error(a_string_including("No resolver", "Widget.id"))
        end
      end
    end
  end
end
