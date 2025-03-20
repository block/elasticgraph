# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphql/resolvers/query_adapter"

module ElasticGraph
  class GraphQL
    module Resolvers
      RSpec.describe QueryAdapter, :query_adapter do
        attr_accessor :schema_artifacts

        before(:context) do
          self.schema_artifacts = generate_schema_artifacts do |schema|
            schema.object_type "Widget" do |t|
              t.field "id", "ID"
              t.field "created_at", "DateTime"
              t.field "workspace_id", "ID"
              t.field "name", "String!"
              t.relates_to_many "child_widgets", "Widget", via: "parent_id", dir: :in, singular: "child_widget"

              t.index "widgets" do |i|
                i.route_with "workspace_id"
                i.default_sort "name", :asc, "created_at", :desc
              end
            end

            schema.object_type "Component" do |t|
              t.field "id", "ID"
              t.field "price", "Int"

              t.index "components" do |i|
                i.default_sort "price", :asc
              end
            end

            schema.union_type "WidgetOrComponent" do |t|
              t.subtypes "Widget", "Component"
              t.root_query_fields plural: "widgets_or_components"
            end

            schema.union_type "ComponentOrWidget" do |t|
              t.subtypes "Component", "Widget"
              t.root_query_fields plural: "components_or_widgets"
            end
          end
        end

        let(:graphql) { build_graphql(schema_artifacts: schema_artifacts) }
        let(:field) { graphql.schema.field_named("Query", "widgets") }
        let(:query_adapter) do
          QueryAdapter.new(
            datastore_query_builder: graphql.datastore_query_builder,
            datastore_query_adapters: graphql.datastore_query_adapters
          )
        end

        describe "#build_query_from" do
          it "returns an `DatastoreQuery`" do
            datastore_query = build_query_from({})
            expect(datastore_query).to be_a(DatastoreQuery)
          end

          it "sets the `search_index_definitions` based on the field type" do
            datastore_query = build_query_from({})
            expect(datastore_query.search_index_definitions).to eq(graphql.schema.type_named("Widget").search_index_definitions)
          end

          describe "sort" do
            it "sets it based on the `order_by` argument" do
              datastore_query = build_query_from({order_by: "created_at_ASC"})
              expect(datastore_query.sort).to eq(["created_at" => {"order" => "asc"}])
            end

            it "defaults the sort order based on the index sort order if `order_by` is not provided" do
              datastore_query = build_query_from({})

              expect(datastore_query.sort).to eq [
                {"name" => {"order" => "asc"}},
                {"created_at" => {"order" => "desc"}}
              ]
            end

            context "on a union type where the subtypes have different default sorts" do
              it "consistently uses the default sort from the alphabetically first index definition" do
                field1 = graphql.schema.field_named("Query", "widgets_or_components")
                field2 = graphql.schema.field_named("Query", "components_or_widgets")

                sort1 = build_query_from({}, field: field1).sort
                sort2 = build_query_from({}, field: field2).sort

                expect(sort1).to eq(sort2).and eq [
                  {"price" => {"order" => "asc"}}
                ]
              end
            end
          end

          it "supports `filter`" do
            datastore_query = build_query_from({filter: {name: {equal_to_any_of: ["ben"]}}})
            expect(datastore_query.filters).to contain_exactly({"name" => {"equal_to_any_of" => ["ben"]}})
          end

          describe "document_pagination" do
            context "on an indexed document field" do
              let(:field) { graphql.schema.field_named("Query", "widgets") }

              it "extracts `after`" do
                datastore_query = build_query_from({after: "ABC"})
                expect(datastore_query.document_pagination).to include(after: "ABC")
              end

              it "extracts `before`" do
                datastore_query = build_query_from({before: "CBA"})
                expect(datastore_query.document_pagination).to include(before: "CBA")
              end

              it "extracts `first`" do
                datastore_query = build_query_from({first: 11})
                expect(datastore_query.document_pagination).to include(first: 11)
              end

              it "extracts `last`" do
                datastore_query = build_query_from({last: 11})
                expect(datastore_query.document_pagination).to include(last: 11)
              end
            end

            context "on an indexed aggregation field" do
              let(:field) { graphql.schema.field_named("Query", "widget_aggregations") }

              it "ignores the pagination arguments since the aggregation adapter handles them for aggregations" do
                datastore_query = build_query_from({
                  first: 3, after: "ABC",
                  last: 2, before: "DEF"
                })

                expect(datastore_query.document_pagination).to eq({})
              end
            end
          end

          it "passes along the `monotonic_clock_deadline` from the `context` to the query" do
            datastore_query = build_query_from({}, context: {monotonic_clock_deadline: 1234})
            expect(datastore_query.monotonic_clock_deadline).to eq 1234
          end

          it "caches the `DatastoreQuery` objects it builds to avoid performing the same expensive work multiple times" do
            datastore_queries = datastore_queries_by_field_for(<<~QUERY, schema_artifacts: schema_artifacts, list_item_count: 10)
              query {
                widgets {
                  edges {
                    node {
                      child_widgets {
                        edges {
                          node {
                            id
                          }
                        }
                      }
                    }
                  }
                }
              }
            QUERY

            child_widget_queries = datastore_queries.fetch("Widget.child_widgets")

            expect(child_widget_queries.size).to eq 10
            expect(child_widget_queries.map(&:__id__).uniq.size).to eq 1
          end

          it "builds different `DatastoreQuery` objects for the same field at different levels" do
            datastore_queries = datastore_queries_by_field_for(<<~QUERY, schema_artifacts: schema_artifacts, list_item_count: 10)
              query {
                widgets {
                  edges {
                    node {
                      child_widgets {
                        edges {
                          node {
                            id

                            child_widgets {
                              edges {
                                node {
                                  id
                                }
                              }
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
            QUERY

            child_widget_queries = datastore_queries.fetch("Widget.child_widgets")

            expect(child_widget_queries.size).to eq 110 # 10 + (10 * 10)
            expect(child_widget_queries.map(&:__id__).uniq.size).to eq 2
          end

          def build_query_from(args, field: self.field, context: {})
            context = ::GraphQL::Query::Context.new(
              query: nil,
              schema: graphql.schema.graphql_schema,
              values: context.merge(elastic_graph_schema: graphql.schema)
            )

            query_adapter.build_query_from(
              field: field,
              args: field.args_to_schema_form(args),
              lookahead: ::GraphQL::Execution::Lookahead::NULL_LOOKAHEAD,
              context: context
            )
          end
        end
      end
    end
  end
end
