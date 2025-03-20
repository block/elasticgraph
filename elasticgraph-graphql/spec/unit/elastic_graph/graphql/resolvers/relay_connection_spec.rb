# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphql/resolvers/relay_connection"
require "support/aggregations_helpers"

module ElasticGraph
  class GraphQL
    module Resolvers
      RSpec.describe RelayConnection do
        include AggregationsHelpers

        describe ".maybe_wrap" do
          attr_accessor :schema_artifacts

          before(:context) do
            self.schema_artifacts = generate_schema_artifacts do |schema|
              schema.object_type "Widget" do |t|
                t.field "id", "ID!"
                t.field "amount_cents", "Int!"
                t.index "widgets" do |i|
                  i.default_sort "amount_cents", :asc
                end
              end

              schema.on_root_query_type do |t|
                # One test relies on `widgets_non_relay`, which isn't defined by default on `Query` so we define it here.
                t.field "widgets_non_relay", "[Widget!]!" do |f|
                  f.resolver = :list_records
                end
              end
            end
          end

          it "uses `SearchResponseAdapterBuilder` to build an adapter when the field is a document relay connection type" do
            allow(Resolvers::RelayConnection::SearchResponseAdapterBuilder).to receive(:build_from).and_call_original

            wrapped = maybe_wrap("widgets")
            expect(wrapped).to be_a Resolvers::RelayConnection::GenericAdapter
            expect(Resolvers::RelayConnection::SearchResponseAdapterBuilder).to have_received(:build_from)
          end

          it "uses `Aggregation::Resolvers::RelayConnectionBuilder` to build an adapter when the field is an aggregation relay connection type" do
            allow(Aggregation::Resolvers::RelayConnectionBuilder).to receive(:build_from_search_response).and_call_original

            wrapped = maybe_wrap("widget_aggregations")
            expect(wrapped).to be_a Resolvers::RelayConnection::GenericAdapter
            expect(Aggregation::Resolvers::RelayConnectionBuilder).to have_received(:build_from_search_response)
          end

          it "does not wrap a datastore response when the field is a non-relay collection" do
            expect(maybe_wrap("widgets_non_relay")).to be_a DatastoreResponse::SearchResponse
          end

          def maybe_wrap(field_name)
            response = DatastoreResponse::SearchResponse.build(build_response_hash([hit_for(300, "w1")]))

            graphql = build_graphql(schema_artifacts: schema_artifacts)
            field = graphql.schema.field_named("Query", field_name)
            context = {schema_element_names: graphql.runtime_metadata.schema_element_names}

            lookahead = ::GraphQL::Execution::Lookahead.new(
              query: nil,
              field: field.graphql_field,
              ast_nodes: []
            )

            query = instance_double(
              "ElasticGraph::GraphQL::DatastoreQuery",
              aggregations: {"widget_aggregations" => aggregation_query_of(name: "widget_aggregations")},
              document_paginator: instance_double(
                "ElasticGraph::GraphQL::DatastoreQuery::DocumentPaginator",
                paginator: instance_double(
                  "ElasticGraph::GraphQL::DatastoreQuery::Paginator"
                )
              )
            )

            RelayConnection.maybe_wrap(response, field: field, context: context, lookahead: lookahead, query: query)
          end

          def build_response_hash(hits)
            {
              "took" => 50,
              "timed_out" => false,
              "_shards" => {
                "total" => 5,
                "successful" => 5,
                "skipped" => 0,
                "failed" => 0
              },
              "hits" => {
                "total" => {
                  "value" => 5,
                  "relation" => "eq"
                },
                "max_score" => nil,
                "hits" => hits
              },
              "aggregations" => {
                "widget_aggregations" => {"buckets" => []}
              }
            }
          end

          def hit_for(amount_cents, id)
            {
              "_index" => "widgets",
              "_type" => "_doc",
              "_id" => id,
              "_score" => nil,
              "_source" => {
                "id" => id,
                "version" => 10,
                "amount_cents" => amount_cents
              },
              "sort" => [amount_cents, id]
            }
          end
        end
      end
    end
  end
end
