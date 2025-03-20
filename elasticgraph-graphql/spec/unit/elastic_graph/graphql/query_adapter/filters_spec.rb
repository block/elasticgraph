# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/constants"
require "elastic_graph/graphql/query_adapter/filters"

module ElasticGraph
  class GraphQL
    class QueryAdapter
      RSpec.describe Filters, :query_adapter do
        attr_accessor :schema_artifacts

        before(:context) do
          self.schema_artifacts = generate_schema_artifacts do |schema|
            schema.enum_type "Size" do |t|
              t.value "LARGE"
              t.value "MEDIUM"
              t.value "SMALL"
            end

            schema.object_type "Options" do |t|
              t.field "color", "String", name_in_index: "rgb_color"
              t.field "size", "String"
            end

            schema.object_type "Person" do |t|
              t.field "name", "String", name_in_index: "name_es"
              t.field "nationality", "String", name_in_index: "nationality_es"
            end

            schema.object_type "Company" do |t|
              t.field "name", "String", name_in_index: "name_es"
              t.field "stock_ticker", "String"
            end

            schema.union_type "Inventor" do |t|
              t.subtypes "Company", "Person"
            end

            schema.object_type "Widget" do |t|
              t.field "id", "ID"
              t.field "name", "String!"
              t.field "count", "Int"
              t.field "tags", "[String]"
              t.field "description", "String!", name_in_index: "description_in_es"
              t.field "options", "Options", name_in_index: "widget_opts"
              t.field "nested_options", "[Options!]" do |f|
                f.mapping type: "nested"
              end

              t.field "inventor", "Inventor"
              t.field "size", "Size"
              t.field "component_id", "ID"
              t.index "widgets"
            end

            schema.object_type "Component" do |t|
              t.field "id", "ID"
              t.field "name", "String"
              t.field "cost", "Int"
              t.field "options", "Options"
              t.relates_to_one "widget", "Widget", via: "component_id", dir: :in

              t.field "widget_name", "String" do |f|
                f.sourced_from "widget", "name"
              end

              t.field "nested_options", "[Options!]" do |f|
                f.mapping type: "nested"
                f.sourced_from "widget", "nested_options"
              end

              t.index "components"
            end

            schema.union_type "WidgetOrComponent" do |t|
              t.root_query_fields plural: "widgets_or_components"
              t.subtypes "Widget", "Component"
            end

            schema.object_type "Unfilterable" do |t|
              t.root_query_fields plural: "unfilterables"
              t.field "id", "ID", filterable: false
              t.index "unfilterables"
            end
          end
        end

        it "translates GraphQL filtering options to datastore filters, converting field names as needed" do
          query = datastore_query_for(:Query, :widgets, <<~QUERY)
            query {
              widgets(filter: {name: {equal_to_any_of: ["abc"]}, description: {equal_to_any_of: ["def"]}}) {
                edges {
                  node {
                    id
                  }
                }
              }
            }
          QUERY

          expect(query.filters.first).to eq({
            "name" => {"equal_to_any_of" => ["abc"]},
            "description_in_es" => {"equal_to_any_of" => ["def"]}
          })
        end

        it "does field name translations at all levels of the filter" do
          query = datastore_query_for(:Query, :widgets, <<~QUERY)
            query {
              widgets(filter: {options: {color: {equal_to_any_of: ["abc"]}, size: {equal_to_any_of: ["def"]}}}) {
                edges {
                  node {
                    id
                  }
                }
              }
            }
          QUERY

          expect(query.filters.first).to eq({"widget_opts" => {
            "rgb_color" => {"equal_to_any_of" => ["abc"]},
            "size" => {"equal_to_any_of" => ["def"]}
          }})
        end

        it "translates enum value strings to enum value objects so that the `runtime_metadata` of the enum value is available to our `FilterInterpreter`" do
          graphql, queries_by_field = graphql_and_datastore_queries_by_field_for(<<~QUERY)
            query {
              widgets(filter: {size: {equal_to_any_of: [LARGE, SMALL, null]}}) {
                nodes {
                  id
                }
              }
            }
          QUERY

          size_input_type = graphql.schema.type_named("SizeInput")

          expect(queries_by_field.fetch("Query.widgets").first.filters.first).to eq({
            "size" => {"equal_to_any_of" => [
              size_input_type.enum_value_named("LARGE"),
              size_input_type.enum_value_named("SMALL"),
              nil
            ]}
          })
        end

        it "translates the sub-expressions of an `any_of`" do
          query = datastore_query_for(:Query, :widgets, <<~QUERY)
            query {
              widgets(filter: {any_of: [
                {name: {equal_to_any_of: ["bob"]}, description: {equal_to_any_of: ["foo"]}},
                {options: {any_of: [
                  {color: {equal_to_any_of: ["red"]}},
                  {size: {equal_to_any_of: ["large"]}}
                ]}}
              ]}) {
                edges {
                  node {
                    id
                  }
                }
              }
            }
          QUERY

          expect(query.filters.first).to eq({
            "any_of" => [
              {
                "name" => {"equal_to_any_of" => ["bob"]},
                "description_in_es" => {"equal_to_any_of" => ["foo"]}
              },
              {
                "widget_opts" => {
                  "any_of" => [
                    {"rgb_color" => {"equal_to_any_of" => ["red"]}},
                    {"size" => {"equal_to_any_of" => ["large"]}}
                  ]
                }
              }
            ]
          })
        end

        it "can translate filter fields that exist on multiple union subtypes on the indexed types" do
          query = datastore_query_for(:Query, :widgets, <<~QUERY)
            query {
              widgets(filter: {inventor: {name: {equal_to_any_of: ["abc"]}}}) {
                edges {
                  node {
                    id
                  }
                }
              }
            }
          QUERY

          expect(query.filters.first).to eq({
            "inventor" => {"name_es" => {"equal_to_any_of" => ["abc"]}}
          })
        end

        it "can translate filter fields that exist on only one of a type union's subtypes on the indexed types" do
          query = datastore_query_for(:Query, :widgets, <<~QUERY)
            query {
              widgets(filter: {inventor: {stock_ticker: {equal_to_any_of: ["abc"]}, nationality: {equal_to_any_of: ["def"]}}}) {
                edges {
                  node {
                    id
                  }
                }
              }
            }
          QUERY

          expect(query.filters.first).to eq({"inventor" => {
            "stock_ticker" => {"equal_to_any_of" => ["abc"]},
            "nationality_es" => {"equal_to_any_of" => ["def"]}
          }})
        end

        it "translates `count` on a list field to `#{LIST_COUNTS_FIELD}` while leaving a `count` schema field unchanged" do
          query = datastore_query_for(:Query, :widgets, <<~QUERY)
            query {
              widgets(filter: {count: {gt: 1}, tags: {count: {gt: 1}}}) {
                nodes { id }
              }
            }
          QUERY

          expect(query.filters.first).to eq({
            "count" => {"gt" => 1},
            "tags" => {LIST_COUNTS_FIELD => {"gt" => 1}}
          })
        end

        context "on a type that has never had any `sourced_from` fields" do
          it "sets no `filters` on the datastore query when the GraphQL query has no filters (but the query field supports arguments)" do
            query = datastore_query_for(:Query, :widgets, <<~QUERY)
              query {
                widgets {
                  edges {
                    node {
                      id
                    }
                  }
                }
              }
            QUERY

            expect(query.filters).to be_empty
          end

          it "sets no `filters` on the datastore query when the GraphQL query field does not have a `filter` argument" do
            graphql, queries_by_field = graphql_and_datastore_queries_by_field_for(<<~QUERY, schema_artifacts: schema_artifacts)
              query {
                unfilterables {
                  edges {
                    node {
                      id
                    }
                  }
                }
              }
            QUERY

            # Verify it does not support a `filter` argument.
            expect(graphql.schema.field_named("Query", "unfilterables").graphql_field.arguments.keys).to contain_exactly(
              "order_by",
              "first", "after",
              "last", "before"
            )

            expect(queries_by_field.keys).to contain_exactly("Query.unfilterables")
            expect(queries_by_field.fetch("Query.unfilterables").size).to eq(1)
            expect(queries_by_field.fetch("Query.unfilterables").first.filters).to be_empty
          end
        end

        context "on a type that has (or has had) `sourced_from` fields" do
          let(:exclude_incomplete_docs_filter) do
            {"__sources" => {"equal_to_any_of" => [SELF_RELATIONSHIP_NAME]}}
          end

          it "excludes incomplete documents as the only filter when the client specifies no filters" do
            query = datastore_query_for(:Query, :components, <<~QUERY)
              query {
                components {
                  nodes {
                    id
                  }
                }
              }
            QUERY

            expect(query.filters).to contain_exactly(exclude_incomplete_docs_filter)
          end

          it "excludes incomplete documents as an additional automatic filter on top of any user-specified filters" do
            query = datastore_query_for(:Query, :components, <<~QUERY)
              query {
                components(filter: {widget_name: {equal_to_any_of: ["thingy"]}}) {
                  nodes {
                    id
                  }
                }
              }
            QUERY

            expect(query.filters).to contain_exactly(
              exclude_incomplete_docs_filter,
              {"widget_name" => {"equal_to_any_of" => ["thingy"]}}
            )
          end

          it "omits the incomplete doc exclusion filter when the specified query filters cannot match an incomplete doc due to requiring a value coming from the `#{SELF_RELATIONSHIP_NAME}` source" do
            query = datastore_query_for(:Query, :components, <<~QUERY)
              query {
                components(filter: {name: {equal_to_any_of: ["thingy"]}}) {
                  nodes {
                    id
                  }
                }
              }
            QUERY

            expect(query.filters).to contain_exactly(
              {"name" => {"equal_to_any_of" => ["thingy"]}}
            )
          end

          it "understands that a filter with `equal_to_any_of: [null]` may still match incomplete documents" do
            query = datastore_query_for(:Query, :components, <<~QUERY)
              query {
                components(filter: {name: {equal_to_any_of: [null]}}) {
                  nodes {
                    id
                  }
                }
              }
            QUERY

            expect(query.filters).to contain_exactly(
              exclude_incomplete_docs_filter,
              {"name" => {"equal_to_any_of" => [nil]}}
            )
          end

          it "understands that a filter with `equal_to_any_of: [null, null]` may still match incomplete documents" do
            query = datastore_query_for(:Query, :components, <<~QUERY)
              query {
                components(filter: {name: {equal_to_any_of: [null, null]}}) {
                  nodes {
                    id
                  }
                }
              }
            QUERY

            expect(query.filters).to contain_exactly(
              exclude_incomplete_docs_filter,
              {"name" => {"equal_to_any_of" => [nil, nil]}}
            )
          end

          it "understands that a filter with `equal_to_any_of: [null, something_else]` may still match incomplete documents" do
            query = datastore_query_for(:Query, :components, <<~QUERY)
              query {
                components(filter: {name: {equal_to_any_of: [null, "thingy"]}}) {
                  nodes {
                    id
                  }
                }
              }
            QUERY

            expect(query.filters).to contain_exactly(
              exclude_incomplete_docs_filter,
              {"name" => {"equal_to_any_of" => [nil, "thingy"]}}
            )
          end

          it "understands that a filter with `equal_to_any_of: []` cannot match incomplete documents" do
            query = datastore_query_for(:Query, :components, <<~QUERY)
              query {
                components(filter: {name: {equal_to_any_of: []}}) {
                  nodes {
                    id
                  }
                }
              }
            QUERY

            expect(query.filters).to contain_exactly(
              {"name" => {"equal_to_any_of" => []}}
            )
          end

          context "when multiple fields are filtered on" do
            it "omits the incomplete doc exclusion filter when none of the field filters could match incomplete documents" do
              query = datastore_query_for(:Query, :components, <<~QUERY)
                query {
                  components(filter: {
                    name: {equal_to_any_of: ["thingy"]}
                    cost: {equal_to_any_of: [7]
                  }}) {
                    nodes {
                      id
                    }
                  }
                }
              QUERY

              expect(query.filters).to contain_exactly(
                {
                  "name" => {"equal_to_any_of" => ["thingy"]},
                  "cost" => {"equal_to_any_of" => [7]}
                }
              )
            end

            it "omits the incomplete doc exclusion filter when some (but not all) of the field filters could match incomplete documents" do
              query = datastore_query_for(:Query, :components, <<~QUERY)
                query {
                  components(filter: {
                    name: {equal_to_any_of: [null]}
                    cost: {equal_to_any_of: [7]
                  }}) {
                    nodes {
                      id
                    }
                  }
                }
              QUERY

              expect(query.filters).to contain_exactly(
                {
                  "name" => {"equal_to_any_of" => [nil]},
                  "cost" => {"equal_to_any_of" => [7]}
                }
              )
            end

            it "includes the incomplete doc exclusion filter when all of the field filters could match incomplete documents" do
              query = datastore_query_for(:Query, :components, <<~QUERY)
                query {
                  components(filter: {
                    name: {equal_to_any_of: [null]}
                    cost: {equal_to_any_of: [null]
                  }}) {
                    nodes {
                      id
                    }
                  }
                }
              QUERY

              expect(query.filters).to contain_exactly(
                exclude_incomplete_docs_filter,
                {
                  "name" => {"equal_to_any_of" => [nil]},
                  "cost" => {"equal_to_any_of" => [nil]}
                }
              )
            end
          end

          it "correctly handles subfields" do
            query = datastore_query_for(:Query, :components, <<~QUERY)
              query {
                components(filter: {options: {size: {equal_to_any_of: ["LARGE"]}}}) {
                  nodes {
                    id
                  }
                }
              }
            QUERY

            expect(query.filters).to contain_exactly(
              {"options" => {"size" => {"equal_to_any_of" => ["LARGE"]}}}
            )

            query = datastore_query_for(:Query, :components, <<~QUERY)
              query {
                components(filter: {options: {size: {equal_to_any_of: [null]}}}) {
                  nodes {
                    id
                  }
                }
              }
            QUERY

            expect(query.filters).to contain_exactly(
              exclude_incomplete_docs_filter,
              {"options" => {"size" => {"equal_to_any_of" => [nil]}}}
            )
          end

          it "understands that a range filter on a self-sourced field cannot match incomplete docs, even if mixed with an operator that can match incomplete docs" do
            query = datastore_query_for(:Query, :components, <<~QUERY)
              query {
                components(filter: {cost: {gt: 7}}) {
                  nodes {
                    id
                  }
                }
              }
            QUERY

            expect(query.filters).to contain_exactly(
              {"cost" => {"gt" => 7}}
            )

            query = datastore_query_for(:Query, :components, <<~QUERY)
              query {
                components(filter: {cost: {gt: 7, equal_to_any_of: [null]}}) {
                  nodes {
                    id
                  }
                }
              }
            QUERY

            expect(query.filters).to contain_exactly(
              {"cost" => {"gt" => 7, "equal_to_any_of" => [nil]}}
            )
          end

          describe "`null` leaves" do
            it "treats `filter: null` as true" do
              query = datastore_query_for(:Query, :components, <<~QUERY)
                query {
                  components(filter: null) {
                    nodes {
                      id
                    }
                  }
                }
              QUERY

              expect(query.filters).to contain_exactly(exclude_incomplete_docs_filter)
            end

            it "treats `field: null` filter as `true`" do
              query = datastore_query_for(:Query, :components, <<~QUERY)
                query {
                  components(filter: {cost: null}) {
                    nodes {
                      id
                    }
                  }
                }
              QUERY

              expect(query.filters).to contain_exactly(
                exclude_incomplete_docs_filter,
                {"cost" => nil}
              )

              query = datastore_query_for(:Query, :components, <<~QUERY)
                query {
                  components(filter: {
                    cost: null
                    name: {equal_to_any_of: ["thingy"]}
                  }) {
                    nodes {
                      id
                    }
                  }
                }
              QUERY

              expect(query.filters).to contain_exactly({"cost" => nil, "name" => {"equal_to_any_of" => ["thingy"]}})
            end

            it "treats `field: {predicate: null}` filter as `true`" do
              query = datastore_query_for(:Query, :components, <<~QUERY)
                query {
                  components(filter: {cost: {equal_to_any_of: null}}) {
                    nodes {
                      id
                    }
                  }
                }
              QUERY

              expect(query.filters).to contain_exactly(
                exclude_incomplete_docs_filter,
                {"cost" => {"equal_to_any_of" => nil}}
              )

              query = datastore_query_for(:Query, :components, <<~QUERY)
                query {
                  components(filter: {
                    cost: {equal_to_any_of: null}
                    name: {equal_to_any_of: ["thingy"]}
                  }) {
                    nodes {
                      id
                    }
                  }
                }
              QUERY

              expect(query.filters).to contain_exactly({
                "cost" => {"equal_to_any_of" => nil},
                "name" => {"equal_to_any_of" => ["thingy"]}
              })
            end

            it "treats `null` filter as `true`" do
              query = datastore_query_for(:Query, :components, <<~QUERY)
                query {
                  components(filter: {options: null}) {
                    nodes {
                      id
                    }
                  }
                }
              QUERY

              expect(query.filters).to contain_exactly(
                exclude_incomplete_docs_filter,
                {"options" => nil}
              )

              query = datastore_query_for(:Query, :components, <<~QUERY)
                query {
                  components(filter: {
                    options: null
                    name: {equal_to_any_of: ["thingy"]}
                  }) {
                    nodes {
                      id
                    }
                  }
                }
              QUERY

              expect(query.filters).to contain_exactly({
                "options" => nil,
                "name" => {"equal_to_any_of" => ["thingy"]}
              })
            end

            it "treats `parent_field: {child_field: null}` as true" do
              query = datastore_query_for(:Query, :components, <<~QUERY)
                query {
                  components(filter: {options: {size: null}}) {
                    nodes {
                      id
                    }
                  }
                }
              QUERY

              expect(query.filters).to contain_exactly(
                {"options" => {"size" => nil}},
                exclude_incomplete_docs_filter
              )

              query = datastore_query_for(:Query, :components, <<~QUERY)
                query {
                  components(filter: {
                    options: {size: null}
                    name: {equal_to_any_of: ["thingy"]}
                  }) {
                    nodes {
                      id
                    }
                  }
                }
              QUERY

              expect(query.filters).to contain_exactly({
                "options" => {"size" => nil},
                "name" => {"equal_to_any_of" => ["thingy"]}
              })
            end

            it "treats `parent_field: {child_field: {predicate: null}}` as true" do
              query = datastore_query_for(:Query, :components, <<~QUERY)
                query {
                  components(filter: {options: {size: {equal_to_any_of: null}}}) {
                    nodes {
                      id
                    }
                  }
                }
              QUERY

              expect(query.filters).to contain_exactly(
                {"options" => {"size" => {"equal_to_any_of" => nil}}},
                exclude_incomplete_docs_filter
              )

              query = datastore_query_for(:Query, :components, <<~QUERY)
                query {
                  components(filter: {
                    options: {size: {equal_to_any_of: null}}
                    name: {equal_to_any_of: ["thingy"]}
                  }) {
                    nodes {
                      id
                    }
                  }
                }
              QUERY

              expect(query.filters).to contain_exactly({
                "options" => {"size" => {"equal_to_any_of" => nil}},
                "name" => {"equal_to_any_of" => ["thingy"]}
              })
            end
          end

          context "when `not` is used" do
            it "still includes the incomplete doc exclusion filter when `not` is applied to a field with an alternate source" do
              # not on the outside...
              query = datastore_query_for(:Query, :components, <<~QUERY)
                query {
                  components(filter: {not: {widget_name: {equal_to_any_of: ["thingy"]}}}) {
                    nodes {
                      id
                    }
                  }
                }
              QUERY

              expect(query.filters).to contain_exactly(
                exclude_incomplete_docs_filter,
                {"not" => {"widget_name" => {"equal_to_any_of" => ["thingy"]}}}
              )

              # not on the inside...
              query = datastore_query_for(:Query, :components, <<~QUERY)
                query {
                  components(filter: {widget_name: {not: {equal_to_any_of: ["thingy"]}}}) {
                    nodes {
                      id
                    }
                  }
                }
              QUERY

              expect(query.filters).to contain_exactly(
                exclude_incomplete_docs_filter,
                {"widget_name" => {"not" => {"equal_to_any_of" => ["thingy"]}}}
              )
            end

            it "still includes the incomplete doc exclusion filter when `not` is applied to self-sourced field with a non-nil filter value" do
              # not on the outside...
              query = datastore_query_for(:Query, :components, <<~QUERY)
                query {
                  components(filter: {not: {name: {equal_to_any_of: ["thingy"]}}}) {
                    nodes {
                      id
                    }
                  }
                }
              QUERY

              expect(query.filters).to contain_exactly(
                exclude_incomplete_docs_filter,
                {"not" => {"name" => {"equal_to_any_of" => ["thingy"]}}}
              )

              # not on the inside...
              query = datastore_query_for(:Query, :components, <<~QUERY)
                query {
                  components(filter: {name: {not: {equal_to_any_of: ["thingy"]}}}) {
                    nodes {
                      id
                    }
                  }
                }
              QUERY

              expect(query.filters).to contain_exactly(
                exclude_incomplete_docs_filter,
                {"name" => {"not" => {"equal_to_any_of" => ["thingy"]}}}
              )
            end

            it "omits the incomplete doc exclusion filter when `not` is applied to self-sourced field with a nil and a non-nil filter value" do
              # not on the outside...
              query = datastore_query_for(:Query, :components, <<~QUERY)
                query {
                  components(filter: {not: {name: {equal_to_any_of: ["thingy", null]}}}) {
                    nodes {
                      id
                    }
                  }
                }
              QUERY

              expect(query.filters).to contain_exactly(
                {"not" => {"name" => {"equal_to_any_of" => ["thingy", nil]}}}
              )

              # not on the inside...
              query = datastore_query_for(:Query, :components, <<~QUERY)
                query {
                  components(filter: {name: {not: {equal_to_any_of: [null, "thingy"]}}}) {
                    nodes {
                      id
                    }
                  }
                }
              QUERY

              expect(query.filters).to contain_exactly(
                {"name" => {"not" => {"equal_to_any_of" => [nil, "thingy"]}}}
              )
            end

            it "omits the incomplete doc exclusion filter when `not` is applied to self-sourced field with a single nil filter value" do
              # not on the outside...
              query = datastore_query_for(:Query, :components, <<~QUERY)
                query {
                  components(filter: {not: {name: {equal_to_any_of: [null]}}}) {
                    nodes {
                      id
                    }
                  }
                }
              QUERY

              expect(query.filters).to contain_exactly(
                {"not" => {"name" => {"equal_to_any_of" => [nil]}}}
              )

              # not on the inside...
              query = datastore_query_for(:Query, :components, <<~QUERY)
                query {
                  components(filter: {name: {not: {equal_to_any_of: [null]}}}) {
                    nodes {
                      id
                    }
                  }
                }
              QUERY

              expect(query.filters).to contain_exactly(
                {"name" => {"not" => {"equal_to_any_of" => [nil]}}}
              )
            end
          end

          context "when `any_of` is used" do
            it "includes the incomplete doc exclusion filter when there are multiple sub-clauses on different fields, because it's hard to optimize and it's safest to include it" do
              query = datastore_query_for(:Query, :components, <<~QUERY)
                query {
                  components(filter: {any_of: [
                    {name: {equal_to_any_of: ["abc"]}},
                    {cost: {equal_to_any_of: [7]}}
                  ]}) {
                    nodes {
                      id
                    }
                  }
                }
              QUERY

              expect(query.filters).to contain_exactly(
                exclude_incomplete_docs_filter,
                {"any_of" => [{"name" => {"equal_to_any_of" => ["abc"]}}, {"cost" => {"equal_to_any_of" => [7]}}]}
              )
            end

            it "omits the incomplete doc exclusion filter when there are multiple sub-clause on the same field, that both can't match incomplete docs" do
              query = datastore_query_for(:Query, :components, <<~QUERY)
                query {
                  components(filter: {any_of: [
                    {cost: {lt: 100}},
                    {cost: {gt: 200}}
                  ]}) {
                    nodes {
                      id
                    }
                  }
                }
              QUERY

              expect(query.filters).to contain_exactly(
                {"any_of" => [{"cost" => {"lt" => 100}}, {"cost" => {"gt" => 200}}]}
              )
            end

            it "includes the incomplete doc exclusion filter when there are multiple sub-clause on the same field, one of which can match incomplete docs" do
              query = datastore_query_for(:Query, :components, <<~QUERY)
                query {
                  components(filter: {any_of: [
                    {cost: {lt: 100}},
                    {cost: {equal_to_any_of: [null]}}
                  ]}) {
                    nodes {
                      id
                    }
                  }
                }
              QUERY

              expect(query.filters).to contain_exactly(
                exclude_incomplete_docs_filter,
                {"any_of" => [{"cost" => {"lt" => 100}}, {"cost" => {"equal_to_any_of" => [nil]}}]}
              )
            end

            it "omits the incomplete doc exclusion filter when there is one sub-clause, that can't match incomplete docs" do
              query = datastore_query_for(:Query, :components, <<~QUERY)
                query {
                  components(filter: {any_of: [
                    {name: {equal_to_any_of: ["abc"]}}
                  ]}) {
                    nodes {
                      id
                    }
                  }
                }
              QUERY

              expect(query.filters).to contain_exactly(
                {"any_of" => [{"name" => {"equal_to_any_of" => ["abc"]}}]}
              )
            end

            it "includes the incomplete doc exclusion filter when there are no sub-clauses, because the filter is treated as `false` for being empty" do
              query = datastore_query_for(:Query, :components, <<~QUERY)
                query {
                  components(filter: {any_of: []}) {
                    nodes {
                      id
                    }
                  }
                }
              QUERY

              expect(query.filters).to contain_exactly(
                exclude_incomplete_docs_filter,
                {"any_of" => []}
              )
            end
          end

          context "when querying a type backed by multiple index definitions" do
            it "includes the incomplete doc exclusion filter if incomplete docs could be hit by the search on at least one of the filters" do
              query = datastore_query_for(:Query, :widgets_or_components, <<~QUERY)
                query {
                  widgets_or_components(filter: {
                    name: {equal_to_any_of: [null]}
                  }) {
                    nodes {
                      __typename
                    }
                  }
                }
              QUERY

              expect(query.filters).to contain_exactly(
                exclude_incomplete_docs_filter,
                {"name" => {"equal_to_any_of" => [nil]}}
              )
            end

            it "omits the incomplete doc exclusion filter if incomplete docs could not be hit by the search on either of the filters" do
              query = datastore_query_for(:Query, :widgets_or_components, <<~QUERY)
                query {
                  widgets_or_components(filter: {
                    name: {equal_to_any_of: ["thingy"]}
                  }) {
                    nodes {
                      __typename
                    }
                  }
                }
              QUERY

              expect(query.filters).to contain_exactly(
                {"name" => {"equal_to_any_of" => ["thingy"]}}
              )
            end
          end
        end

        shared_examples_for "filtering on a `nested` field" do |root_field|
          it "translates the sub-expressions of an `all_of`" do
            query = datastore_query_for(:Query, root_field, <<~QUERY)
              query {
                #{root_field}(filter: {nested_options: {all_of: [
                  {any_satisfy: {color: {equal_to_any_of: ["red"]}}},
                  {any_satisfy: {color: {equal_to_any_of: ["green"]}}}
                ]}}) {
                  total_edge_count
                }
              }
            QUERY

            expect(query.filters.first).to eq({"nested_options" => {"all_of" => [
              # the `name_in_index` of `color` is `rgb_color`.
              {"any_satisfy" => {"rgb_color" => {"equal_to_any_of" => ["red"]}}},
              {"any_satisfy" => {"rgb_color" => {"equal_to_any_of" => ["green"]}}}
            ]}})
          end

          it "translates an `any_satisfy` filter" do
            query = datastore_query_for(:Query, root_field, <<~QUERY)
              query {
                #{root_field}(filter: {
                  nested_options: {
                    any_satisfy: {
                      color: {equal_to_any_of: ["red"]}
                    }
                  }
                }) {
                  total_edge_count
                }
              }
            QUERY

            expect(query.filters.first).to eq({
              "nested_options" => {"any_satisfy" => {"rgb_color" => {"equal_to_any_of" => ["red"]}}}
            })
          end

          it "translates a `count` filter" do
            query = datastore_query_for(:Query, root_field, <<~QUERY)
              query {
                #{root_field}(filter: {
                  nested_options: {count: {equal_to_any_of: [0]}}
                }) {
                  total_edge_count
                }
              }
            QUERY

            expect(query.filters.first).to eq({
              "nested_options" => {"__counts" => {"equal_to_any_of" => [0]}}
            })
          end
        end

        context "on a `nested` field which is directly indexed" do
          include_examples "filtering on a `nested` field", :widgets
        end

        context "on a `nested` field which is sourced from another type" do
          include_examples "filtering on a `nested` field", :components
        end

        def graphql_and_datastore_queries_by_field_for(graphql_query, **graphql_opts)
          super(graphql_query, schema_artifacts: schema_artifacts, **graphql_opts)
        end

        def datastore_query_for(type, field, graphql_query)
          super(
            schema_artifacts: schema_artifacts,
            graphql_query: graphql_query,
            type: type,
            field: field,
          )
        end
      end
    end
  end
end
