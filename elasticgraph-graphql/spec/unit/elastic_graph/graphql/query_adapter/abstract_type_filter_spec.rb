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
        attr_accessor :schema_artifacts

        before(:context) do
          self.schema_artifacts = generate_schema_artifacts do |schema|
            # A concrete type with its own dedicated index.
            schema.object_type "Widget" do |t|
              t.field "id", "ID!"
              t.root_query_fields plural: "widgets"
              t.index "widgets"
            end

            # A union whose subtypes all share one index — no __typename filter needed.
            schema.object_type "Person" do |t|
              t.field "id", "ID!"
            end

            schema.object_type "Company" do |t|
              t.field "id", "ID!"
            end

            schema.union_type "Inventor" do |t|
              t.subtypes "Person", "Company"
              t.root_query_fields plural: "inventors"
              t.index "inventors"
            end

            # An interface hierarchy where `Store` shares the `channels` index with `Wholesaler`,
            # requiring a __typename filter when querying stores.
            # `PhysicalStore` has its own dedicated index, so its documents will not have __typename.
            schema.interface_type "Channel" do |t|
              t.field "id", "ID!"
              t.root_query_fields plural: "channels"
              t.index "channels"
            end

            schema.object_type "Wholesaler" do |t|
              t.implements "Channel"
              t.field "id", "ID!"
            end

            schema.interface_type "Store" do |t|
              t.implements "Channel"
              t.field "id", "ID!"
              t.root_query_fields plural: "stores"
            end

            schema.object_type "OnlineStore" do |t|
              t.implements "Store"
              t.field "id", "ID!"
            end

            schema.object_type "PhysicalStore" do |t|
              t.implements "Store"
              t.field "id", "ID!"
              t.index "physical_stores"
            end
          end
        end

        context "when querying a concrete type" do
          it "does not apply a __typename filter" do
            query = datastore_query_for(:Query, :widgets, <<~QUERY)
              query { widgets { edges { node { id } } } }
            QUERY

            expect(query.internal_filters).to be_empty
          end
        end

        context "when querying an abstract type whose subtypes all share one index" do
          it "does not apply a __typename filter" do
            query = datastore_query_for(:Query, :inventors, <<~QUERY)
              query { inventors { edges { node { ... on Person { id } ... on Company { id } } } } }
            QUERY

            expect(query.internal_filters).to be_empty
          end
        end

        context "when querying an abstract type that shares an index with a sibling type" do
          it "applies a __typename filter scoped to the queried type's concrete subtypes, including nil for subtypes with dedicated indexes" do
            query = datastore_query_for(:Query, :stores, <<~QUERY)
              query { stores { edges { node { id } } } }
            QUERY

            typename_filter = query.internal_filters.find { |f| f.key?("__typename") }
            expect(typename_filter).not_to be_nil
            expect(typename_filter.dig("__typename", "equal_to_any_of")).to contain_exactly(nil, "OnlineStore", "PhysicalStore")
          end

          it "applies a __typename filter when querying the root abstract type" do
            query = datastore_query_for(:Query, :channels, <<~QUERY)
              query { channels { edges { node { id } } } }
            QUERY

            expect(query.internal_filters).not_to be_empty
          end

          it "applies a __typename filter on aggregations of the abstract type" do
            query = datastore_query_for(:Query, :store_aggregations, <<~QUERY)
              query { store_aggregations { nodes { count } } }
            QUERY

            typename_filter = query.internal_filters.find { |f| f.key?("__typename") }
            expect(typename_filter).not_to be_nil
            expect(typename_filter.dig("__typename", "equal_to_any_of")).to contain_exactly(nil, "OnlineStore", "PhysicalStore")
          end
        end

        context "when calling non_subtypes_in_shared_index" do
          it "excludes the type itself and its subtypes from the result" do
            schema = build_graphql(schema_artifacts: schema_artifacts).schema
            store = schema.type_named("Store")

            result = store.non_subtypes_in_shared_index
            expect(result).not_to include(store)
            expect(result).not_to include(schema.type_named("OnlineStore"))
            expect(result).not_to include(schema.type_named("PhysicalStore"))
            expect(result).to include(schema.type_named("Wholesaler"))
          end
        end

        private

        def graphql_and_datastore_queries_by_field_for(graphql_query, **graphql_opts)
          super(graphql_query, schema_artifacts: schema_artifacts, **graphql_opts)
        end

        def datastore_query_for(type, field, graphql_query)
          super(
            schema_artifacts: schema_artifacts,
            graphql_query: graphql_query,
            type: type,
            field: field
          )
        end
      end
    end
  end
end
