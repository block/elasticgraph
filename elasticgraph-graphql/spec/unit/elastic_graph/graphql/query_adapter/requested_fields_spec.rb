# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphql/query_adapter/requested_fields"

module ElasticGraph
  class GraphQL
    class QueryAdapter
      RSpec.describe RequestedFields, :query_adapter do
        attr_accessor :schema_artifacts

        before(:context) do
          self.schema_artifacts = generate_schema_artifacts do |schema|
            schema.object_type "WidgetOptions" do |t|
              t.field "size", "String"
              t.field "color", "String"
            end

            schema.object_type "Person" do |t|
              t.implements "NamedInventor"
              t.field "name", "String"
              t.field "nationality", "String"
            end

            schema.object_type "Company" do |t|
              t.implements "NamedInventor"
              t.field "name", "String"
              t.field "stock_ticker", "String"
            end

            schema.union_type "Inventor" do |t|
              t.subtypes "Person", "Company"
            end

            # Embedded interface type.
            schema.interface_type "NamedInventor" do |t|
              t.field "name", "String"
            end

            # Indexed interfae type.
            schema.interface_type "NamedEntity" do |t|
              t.root_query_fields plural: "named_entities"
              t.field "id", "ID"
              t.field "name", "String"
            end

            schema.object_type "Widget" do |t|
              t.implements "NamedEntity"
              t.field "id", "ID"
              t.field "name", "String"
              t.field "created_at", "DateTime"
              t.field "last_name", "String"
              t.field "amount_cents", "Int"
              t.field "options", "WidgetOptions"
              t.field "inventor", "Inventor"
              t.field "named_inventor", "NamedInventor"
              t.relates_to_many "components", "Component", via: "component_ids", dir: :out, singular: "component"
              t.relates_to_many "child_widgets", "Widget", via: "parent_id", dir: :in, singular: "child_widget"
              t.relates_to_one "parent_widget", "Widget", via: "parent_id", dir: :out
              t.index "widgets"
            end

            schema.object_type "MechanicalPart" do |t|
              t.implements "NamedEntity"
              t.field "id", "ID"
              t.field "name", "String"
              t.field "created_at", "DateTime"
              t.index "mechanical_parts"
            end

            schema.object_type "ElectricalPart" do |t|
              t.implements "NamedEntity"
              t.field "id", "ID"
              t.field "name", "String"
              t.field "created_at", "DateTime"
              t.field "voltage", "Int"
              t.index "electrical_parts"
            end

            schema.union_type "Part" do |t|
              t.subtypes "MechanicalPart", "ElectricalPart"
            end

            schema.object_type "Component" do |t|
              t.implements "NamedEntity"
              t.field "id", "ID"
              t.field "name", "String"
              t.field "last_name", "String"
              t.relates_to_one "widget", "Widget", via: "component_ids", dir: :in
              t.relates_to_many "parts", "Part", via: "part_ids", dir: :out, singular: "part"
              t.index "components"
            end
          end
        end

        it "can request the fields under `edges.node` for a relay connection" do
          query = datastore_query_for(:Query, :widgets, <<~QUERY)
            query {
              widgets {
                edges {
                  node {
                    id
                    name
                  }
                }
              }
            }
          QUERY

          expect(query.requested_fields).to contain_exactly("id", "name")
          expect(query.individual_docs_needed).to be true
          expect(query.total_document_count_needed).to be false
        end

        it "can request the fields under `nodes` for a relay connection" do
          query = datastore_query_for(:Query, :widgets, <<~QUERY)
            query {
              widgets {
                nodes {
                  id
                  name
                }
              }
            }
          QUERY

          expect(query.requested_fields).to contain_exactly("id", "name")
          expect(query.individual_docs_needed).to be true
          expect(query.total_document_count_needed).to be false
        end

        it "does not request the fields under `edges.node` for an aggregations query" do
          query = datastore_query_for(:Query, :widget_aggregations, <<~QUERY)
            query {
              widget_aggregations {
                edges {
                  node {
                    grouped_by {
                      name
                    }

                    aggregated_values {
                      amount_cents {
                        exact_sum
                      }
                    }
                  }
                }
              }
            }
          QUERY

          expect(query.requested_fields).to be_empty
          expect(query.individual_docs_needed).to be false
          expect(query.total_document_count_needed).to be false
        end

        it "includes a path prefix when requesting a field under an embedded object" do
          query = datastore_query_for(:Query, :widgets, <<~QUERY)
            query {
              widgets {
                edges {
                  node {
                    id
                    name
                    options {
                      size
                    }
                  }
                }
              }
            }
          QUERY

          expect(query.requested_fields).to contain_exactly("id", "name", "options.size")
          expect(query.individual_docs_needed).to be true
          expect(query.total_document_count_needed).to be false
        end

        it "requests __typename when the client asks for __typename on a union or interface (but not when they ask for __typename on an object)" do
          query = datastore_query_for(:Query, :widgets, <<~QUERY)
            query {
              widgets {
                edges {
                  node {
                    id

                    options {
                      __typename
                    }

                    inventor {
                      __typename
                    }

                    named_inventor {
                      __typename
                    }
                  }
                }
              }
            }
          QUERY

          expect(query.requested_fields).to contain_exactly("id", "inventor.__typename", "named_inventor.__typename")
          expect(query.individual_docs_needed).to be true
          expect(query.total_document_count_needed).to be false
        end

        it "requests the set union of fields from union subtypes" do
          query = datastore_query_for(:Query, :widgets, <<~QUERY)
            query {
              widgets {
                edges {
                  node {
                    inventor {
                      __typename

                      ... on Person {
                        name
                        nationality
                      }

                      ... on Company {
                        name
                        stock_ticker
                      }
                    }
                  }
                }
              }
            }
          QUERY

          expect(query.requested_fields).to contain_exactly("inventor.__typename", "inventor.name", "inventor.nationality", "inventor.stock_ticker")
          expect(query.individual_docs_needed).to be true
          expect(query.total_document_count_needed).to be false
        end

        it "requests the set union of fields from interface subtypes" do
          query = datastore_query_for(:Query, :widgets, <<~QUERY)
            query {
              widgets {
                edges {
                  node {
                    named_inventor {
                      __typename
                      name

                      ... on Person {
                        nationality
                      }

                      ... on Company {
                        stock_ticker
                      }
                    }
                  }
                }
              }
            }
          QUERY

          expect(query.requested_fields).to contain_exactly("named_inventor.__typename", "named_inventor.name", "named_inventor.nationality", "named_inventor.stock_ticker")
          expect(query.individual_docs_needed).to be true
          expect(query.total_document_count_needed).to be false
        end

        it "always requests __typename for union fields even if the GraphQL query is not asking for it so that the ElasticGraph framework can determine the subtype" do
          query = datastore_query_for(:Query, :widgets, <<~QUERY)
            query {
              widgets {
                edges {
                  node {
                    inventor {
                      ... on Person {
                        nationality
                      }

                      ... on Company {
                        stock_ticker
                      }
                    }
                  }
                }
              }
            }
          QUERY

          expect(query.requested_fields).to contain_exactly("inventor.__typename", "inventor.nationality", "inventor.stock_ticker")
          expect(query.individual_docs_needed).to be true
          expect(query.total_document_count_needed).to be false
        end

        it "always requests __typename for interface fields even if the GraphQL query is not asking for it so that the ElasticGraph framework can determine the subtype" do
          query = datastore_query_for(:Query, :widgets, <<~QUERY)
            query {
              widgets {
                edges {
                  node {
                    named_inventor {
                      ... on Person {
                        nationality
                      }

                      ... on Company {
                        stock_ticker
                      }
                    }
                  }
                }
              }
            }
          QUERY

          expect(query.requested_fields).to contain_exactly("named_inventor.__typename", "named_inventor.nationality", "named_inventor.stock_ticker")
          expect(query.individual_docs_needed).to be true
          expect(query.total_document_count_needed).to be false
        end

        it "ignores relay connection sub-fields that are not directly under `edges.node` (e.g. `page_info`)" do
          query = datastore_query_for(:Query, :widgets, <<~QUERY)
            query {
              widgets {
                page_info {
                  has_next_page
                }
                edges {
                  node {
                    id
                    name
                  }
                  cursor
                }
              }
            }
          QUERY

          expect(query.requested_fields).to contain_exactly("id", "name")
          expect(query.individual_docs_needed).to be true
          expect(query.total_document_count_needed).to be false
        end

        it "requests no fields when only fetching page_info on a relay connection" do
          query = datastore_query_for(:Query, :widgets, <<~QUERY)
            query {
              widgets {
                page_info {
                  has_next_page
                }
                edges {
                  cursor
                }
              }
            }
          QUERY

          expect(query.requested_fields).to be_empty
          expect(query.total_document_count_needed).to be false
        end

        describe "individual_docs_needed" do
          it "sets `individual_docs_needed = false` when no fields are requested, no cursor is requested and page info is not requested" do
            query = datastore_query_for(:Query, :widgets, <<~QUERY)
              query {
                widgets {
                  __typename
                }
              }
            QUERY

            expect(query.individual_docs_needed).to be false
          end

          it "sets `individual_docs_needed = true` when a node field is requested" do
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

            expect(query.individual_docs_needed).to be true
          end

          it "sets `individual_docs_needed = true` when an edge cursor is requested" do
            query = datastore_query_for(:Query, :widgets, <<~QUERY)
              query {
                widgets {
                  edges {
                    cursor
                  }
                }
              }
            QUERY

            expect(query.individual_docs_needed).to be true
          end

          %w[start_cursor end_cursor has_next_page has_previous_page].each do |page_info_field|
            it "sets `individual_docs_needed = true` when page info field #{page_info_field} is requested" do
              query = datastore_query_for(:Query, :widgets, <<~QUERY)
                query {
                  widgets {
                    page_info {
                      #{page_info_field}
                    }
                  }
                }
              QUERY

              expect(query.individual_docs_needed).to be true
            end
          end
        end

        describe "total_document_count_needed" do
          it "is set to false when `total_edge_count` is not requested" do
            query = datastore_query_for(:Query, :widgets, <<~QUERY)
              query {
                widgets {
                  edges {
                    node {
                      id
                      name
                    }
                  }
                }
              }
            QUERY

            expect(query.total_document_count_needed).to be false
          end

          it "is set to true when `total_edge_count` is requested" do
            query = datastore_query_for(:Query, :widgets, <<~QUERY)
              query {
                widgets {
                  total_edge_count
                  edges {
                    node {
                      id
                      name
                    }
                  }
                }
              }
            QUERY

            expect(query.total_document_count_needed).to be true
          end

          it "is set to false when `total_edge_count` is requested in a nested object" do
            query = datastore_query_for(:Query, :widgets, <<~QUERY)
              query {
                widgets {
                  edges {
                    node {
                      components {
                        total_edge_count
                      }
                    }
                  }
                }
              }
            QUERY

            expect(query.total_document_count_needed).to be false
          end
        end

        context "for a nested relation field with an outbound foreign key" do
          it "includes the foreign key field" do
            query = datastore_query_for(:Query, :widgets, <<~QUERY)
              query {
                widgets {
                  edges {
                    node {
                      name

                      components {
                        edges {
                          node {
                            last_name
                          }
                        }
                      }
                    }
                  }
                }
              }
            QUERY

            expect(query.requested_fields).to contain_exactly("name", "component_ids")
            expect(query.individual_docs_needed).to be true
            expect(query.total_document_count_needed).to be false
          end

          it "also includes `id` if it is a self-referential relation" do
            query = datastore_query_for(:Query, :widgets, <<~QUERY)
              query {
                widgets {
                  edges {
                    node {
                      name

                      parent_widget {
                        amount_cents
                      }
                    }
                  }
                }
              }
            QUERY

            expect(query.requested_fields).to contain_exactly("name", "id", "parent_id")
            expect(query.individual_docs_needed).to be true
            expect(query.total_document_count_needed).to be false
          end
        end

        context "for a nested relation field with an inbound foreign key" do
          it "includes the `id` field" do
            query = datastore_query_for(:Query, :components, <<~QUERY)
              query {
                components {
                  edges {
                    node {
                      last_name

                      widget {
                        name
                      }
                    }
                  }
                }
              }
            QUERY

            expect(query.requested_fields).to contain_exactly("last_name", "id")
            expect(query.individual_docs_needed).to be true
            expect(query.total_document_count_needed).to be false
          end

          it "also includes foreign key field if it is a self-referential relation" do
            query = datastore_query_for(:Query, :widgets, <<~QUERY)
              query {
                widgets {
                  edges {
                    node {
                      name

                      child_widgets {
                        edges {
                          node {
                            amount_cents
                          }
                        }
                      }
                    }
                  }
                }
              }
            QUERY

            expect(query.requested_fields).to contain_exactly("name", "id", "parent_id")
            expect(query.individual_docs_needed).to be true
            expect(query.total_document_count_needed).to be false
          end
        end

        context "when building a query for a nested relation" do
          it "requests the fields required based on its sub-fields" do
            query = datastore_query_for(:Widget, :components, <<~QUERY)
              query {
                widgets {
                  edges {
                    node {
                      id
                      name
                      components {
                        edges {
                          node {
                            last_name

                            widget {
                              amount_cents
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
            QUERY

            expect(query.requested_fields).to contain_exactly("last_name", "id")
            expect(query.individual_docs_needed).to be true
            expect(query.total_document_count_needed).to be false
          end
        end

        context "when building a query for a nested relation with a nested type union relay connection relation" do
          it "requests the foreign key field rather than the sub-fields from the fragments" do
            query = datastore_query_for(:Widget, :components, <<~QUERY)
              query {
                widgets {
                  edges {
                    node {
                      components {
                        edges {
                          node {
                            last_name

                            parts {
                              edges {
                                node {
                                  ... on MechanicalPart {
                                    name
                                  }

                                  ... on ElectricalPart {
                                    name
                                    voltage
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
              }
            QUERY

            expect(query.requested_fields).to contain_exactly("last_name", "part_ids")
            expect(query.individual_docs_needed).to be true
            expect(query.total_document_count_needed).to be false
          end
        end

        context "when building a query for a a nested type union relay connection relation" do
          it "requests the set union of fields from each type fragment" do
            query = datastore_query_for(:Component, :parts, <<~QUERY)
              query {
                widgets {
                  edges {
                    node {
                      components {
                        edges {
                          node {
                            last_name

                            parts {
                              edges {
                                node {
                                  ... on MechanicalPart {
                                    name
                                  }

                                  ... on ElectricalPart {
                                    name
                                    voltage
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
              }
            QUERY

            expect(query.requested_fields).to contain_exactly("name", "voltage", "__typename")
            expect(query.individual_docs_needed).to be true
            expect(query.total_document_count_needed).to be false
          end
        end

        it "ignores built-in introspection fields as they never exist in the datastore" do
          query = datastore_query_for(:Query, :widgets, <<~QUERY)
            query {
              widgets {
                edges {
                  node {
                    id
                    name
                    __typename
                  }
                }
              }
            }
          QUERY

          expect(query.requested_fields).to contain_exactly("id", "name")
          expect(query.individual_docs_needed).to be true
          expect(query.total_document_count_needed).to be false
        end

        it "only identifies requested fields for query nodes of indexed types" do
          graphql_fields = graphql_fields_with_request_fields_for(<<~QUERY)
            query {
              components {
                edges {
                  node {
                    id
                  }
                }
              }

              widgets {
                page_info {
                  has_next_page
                }

                edges {
                  node {
                    id

                    components {
                      edges {
                        node {
                          last_name

                          parts {
                            edges {
                              node {
                                ... on MechanicalPart {
                                  name
                                }

                                ... on ElectricalPart {
                                  name
                                  voltage
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
            }
          QUERY

          expect(graphql_fields).to contain_exactly(
            "Query.widgets",
            "Query.components",
            "Widget.components",
            "Component.parts"
          )
        end

        def datastore_query_for(type, field, graphql_query)
          super(
            schema_artifacts: schema_artifacts,
            graphql_query: graphql_query,
            type: type,
            field: field,
          )
        end

        def graphql_fields_with_request_fields_for(graphql_query)
          queries_by_graphql_field = datastore_queries_by_field_for(graphql_query, schema_artifacts: schema_artifacts)

          queries_by_graphql_field.reject do |field, queries|
            queries.all? { |q| q.requested_fields.empty? }
          end.keys
        end
      end
    end
  end
end
