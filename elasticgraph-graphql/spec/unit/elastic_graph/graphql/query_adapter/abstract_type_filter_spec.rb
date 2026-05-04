# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphql/query_adapter/abstract_type_filter"

module ElasticGraph
  class GraphQL
    class QueryAdapter
      RSpec.describe AbstractTypeFilter, :query_adapter do
        context "when querying a concrete type" do
          it "does not apply a __typename filter" do
            query = datastore_query_for(:Query, :widgets, "query { widgets { edges { node { id } } } }")

            expect(typename_filter_from(query)).to be_nil
          end
        end

        context "when querying an abstract type with a shared index but all types in that index are subtypes" do
          it "does not apply a __typename filter" do
            query = datastore_query_for(:Query, :distribution_channels, "query { distribution_channels { edges { node { id } } } }")

            expect(typename_filter_from(query)).to be_nil
          end
        end

        context "when querying an abstract type that shares a search index with a non-subtype" do
          it "applies a __typename filter scoped to the queried type's concrete subtypes, including nil for subtypes with dedicated indexes" do
            query = datastore_query_for(:Query, :retailers, "query { retailers { edges { node { id } } } }")

            expect(typename_filter_from(query)).to contain_exactly(nil, "OnlineStore", "PhysicalStore")
          end

          it "applies a __typename filter on aggregations of this kind of abstract type" do
            query = datastore_query_for(:Query, :retail_aggregations, "query { retail_aggregations { nodes { count } } }")

            expect(typename_filter_from(query)).to contain_exactly(nil, "OnlineStore", "PhysicalStore")
          end

          it "omits nil from the __typename filter when all queried indexes store multiple types" do
            query = datastore_query_for(:Query, :wholesalers, "query { wholesalers { edges { node { id } } } }")

            expect(typename_filter_from(query)).to contain_exactly("DirectWholesaler", "BrokerWholesaler")
          end
        end

        private

        def datastore_query_for(type, field, graphql_query)
          super(
            schema_artifacts: stock_schema_artifacts,
            graphql_query: graphql_query,
            type: type,
            field: field
          )
        end

        def typename_filter_from(query)
          filter = query.internal_filters.find { |f| f.key?("__typename") }
          filter&.dig("__typename", "equal_to_any_of")
        end
      end
    end
  end
end
