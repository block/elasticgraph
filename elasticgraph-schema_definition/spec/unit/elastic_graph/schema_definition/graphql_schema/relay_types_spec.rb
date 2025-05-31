# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require_relative "graphql_schema_spec_support"
require "elastic_graph/schema_definition/test_support"

module ElasticGraph
  module SchemaDefinition
    RSpec.describe "GraphQL schema generation", "relay types" do
      include_context "GraphQL schema spec support"

      with_both_casing_forms do
        it "defines `*Edge` types for each defined `object_type`" do
          result = define_schema do |api|
            api.object_type "Widget" do |t|
              t.field "id", "ID!"
              t.index "widgets"
            end
          end

          expect(edge_type_from(result, "Widget", include_docs: true)).to eq(<<~EOS.strip)
            """
            Represents a specific `Widget` in the context of a `WidgetConnection`,
            providing access to both the `Widget` and query-specific information such as the pagination `Cursor`.

            See the [Relay GraphQL Cursor Connections
            Specification](https://relay.dev/graphql/connections.htm#sec-Edge-Types) for more info.
            """
            type WidgetEdge {
              """
              The `Widget` of this edge.
              """
              #{schema_elements.node}: Widget
              """
              The `Cursor` of this `Widget`. This can be passed in the next query as
              a `before` or `after` argument to continue paginating from this `Widget`.
              """
              #{schema_elements.cursor}: Cursor
              """
              All search highlights for this `Widget`, indicating where in the indexed document the query matched.
              """
              #{schema_elements.all_highlights}: [SearchHighlight!]!
              """
              Specific search highlights for this `Widget`, providing matching snippets for the requested fields.
              """
              #{schema_elements.highlights}: WidgetHighlights
            }
          EOS
        end

        it "defines Edge types for indexed union types" do
          result = define_schema do |api|
            api.object_type "Person" do |t|
              t.field "id", "ID!"
              t.field "name", "String"
              t.field "age", "Int"
              t.field "nationality", "String"
              t.index "people"
            end

            api.object_type "Company" do |t|
              t.field "id", "ID!"
              t.field "name", "String"
              t.field "age", "Int"
              t.field "stock_ticker", "String"
              t.index "companies"
            end

            api.union_type "Inventor" do |t|
              t.subtypes "Person", "Company"
            end
          end

          expect(edge_type_from(result, "Inventor")).to eq(<<~EOS.strip)
            type InventorEdge {
              #{schema_elements.node}: Inventor
              #{schema_elements.cursor}: Cursor
              #{schema_elements.all_highlights}: [SearchHighlight!]!
              #{schema_elements.highlights}: InventorHighlights
            }
          EOS
        end

        it "defines `*Edge` types for each indexed aggregation type" do
          result = define_schema do |api|
            api.object_type "Widget" do |t|
              t.field "id", "ID!"
              t.field "int", "Int", aggregatable: true
              t.index "widgets"
            end
          end

          expect(aggregation_edge_type_from(result, "Widget", include_docs: true)).to eq(<<~EOS.strip)
            """
            Represents a specific `WidgetAggregation` in the context of a `WidgetAggregationConnection`,
            providing access to both the `WidgetAggregation` and query-specific information such as the pagination `Cursor`.

            See the [Relay GraphQL Cursor Connections
            Specification](https://relay.dev/graphql/connections.htm#sec-Edge-Types) for more info.
            """
            type WidgetAggregationEdge {
              """
              The `WidgetAggregation` of this edge.
              """
              node: WidgetAggregation
              """
              The `Cursor` of this `WidgetAggregation`. This can be passed in the next query as
              a `before` or `after` argument to continue paginating from this `WidgetAggregation`.
              """
              cursor: Cursor
            }
          EOS
        end

        it "does not define Edge types for embedded union types" do
          result = define_schema do |api|
            api.object_type "Person" do |t|
              t.field "name", "String"
              t.field "age", "Int"
              t.field "nationality", "String"
            end

            api.object_type "Company" do |t|
              t.field "name", "String"
              t.field "age", "Int"
              t.field "stock_ticker", "String"
            end

            api.union_type "Inventor" do |t|
              t.subtypes "Person", "Company"
            end
          end

          expect(edge_type_from(result, "Inventor")).to eq(nil)
        end

        it "defines `*Connection` types for each defined `object_type`" do
          result = define_schema do |api|
            api.object_type "Widget" do |t|
              t.field "id", "ID!"
              t.field "cost_amount", "Int"
              t.field "created_at", "DateTime"
              t.index "widgets"
            end
          end

          expect(connection_type_from(result, "Widget", include_docs: true)).to eq(<<~EOS.strip)
            """
            Represents a paginated collection of `Widget` results.

            See the [Relay GraphQL Cursor Connections
            Specification](https://relay.dev/graphql/connections.htm#sec-Connection-Types) for more info.
            """
            type WidgetConnection {
              """
              Wraps a specific `Widget` to pair it with its pagination cursor.
              """
              #{schema_elements.edges}: [WidgetEdge!]!
              """
              The list of `Widget` results.
              """
              #{schema_elements.nodes}: [Widget!]!
              """
              Provides pagination-related information.
              """
              #{schema_elements.page_info}: PageInfo!
              """
              The total number of edges available in this connection to paginate over.
              """
              #{schema_elements.total_edge_count}: JsonSafeLong!
            }
          EOS
        end

        it "mentions the possible efficiency improvement of querying a derived index in the aggregation comments when it applies" do
          result = define_schema do |api|
            api.object_type "WidgetWorkspace" do |t|
              t.field "id", "ID!"
              t.field "currencies", "[String!]!"
            end

            api.object_type "Widget" do |t|
              t.field "id", "ID!"
              t.field "workspace_id", "ID"
              t.field "cost_currency", "String"
              t.index "widgets"
              t.derive_indexed_type_fields "WidgetWorkspace", from_id: "workspace_id" do |derive|
                derive.append_only_set "currencies", from: "cost_currency"
              end
            end
          end

          expect(aggregation_efficency_hint_for(result, "widget_aggregations")).to eq(<<~EOS.strip)
            """
            Aggregations over the `widgets` data:

            > Fetches `Widget`s based on the provided arguments.

            Note: aggregation queries are relatively expensive, and some fields have been pre-aggregated to allow
            more efficient queries for some common aggregation cases:

              - The root `#{correctly_cased "widget_workspaces"}` field groups by `workspace_id`
            """
          EOS
        end

        it "respects a type name override when generating the aggregation efficiency hints" do
          result = define_schema(type_name_overrides: {WidgetWorkspace: "WorkspaceOfWidget"}) do |api|
            api.object_type "WidgetWorkspace" do |t|
              t.field "id", "ID!"
              t.field "currencies", "[String!]!"
            end

            api.object_type "Widget" do |t|
              t.field "id", "ID!"
              t.field "workspace_id", "ID"
              t.field "cost_currency", "String"
              t.index "widgets"
              t.derive_indexed_type_fields "WidgetWorkspace", from_id: "workspace_id" do |derive|
                derive.append_only_set "currencies", from: "cost_currency"
              end
            end
          end

          expect(aggregation_efficency_hint_for(result, "widget_aggregations")).to eq(<<~EOS.strip)
            """
            Aggregations over the `widgets` data:

            > Fetches `Widget`s based on the provided arguments.

            Note: aggregation queries are relatively expensive, and some fields have been pre-aggregated to allow
            more efficient queries for some common aggregation cases:

              - The root `#{correctly_cased "workspace_of_widgets"}` field groups by `workspace_id`
            """
          EOS
        end

        it "defines Connection types for indexed union types" do
          result = define_schema do |api|
            api.object_type "Person" do |t|
              t.field "id", "ID!"
              t.field "name", "String"
              t.field "age", "Int"
              t.field "nationality", "String", groupable: true
              t.index "people"
            end

            api.object_type "Company" do |t|
              t.field "id", "ID!"
              t.field "name", "String"
              t.field "age", "Int"
              t.field "stock_ticker", "String"
              t.index "companies"
            end

            api.union_type "Inventor" do |t|
              t.subtypes "Person", "Company"
            end
          end

          expect(connection_type_from(result, "Inventor")).to eq(<<~EOS.strip)
            type InventorConnection {
              #{schema_elements.edges}: [InventorEdge!]!
              #{schema_elements.nodes}: [Inventor!]!
              #{schema_elements.page_info}: PageInfo!
              #{schema_elements.total_edge_count}: JsonSafeLong!
            }
          EOS
        end

        it "defines Connection types for indexed interface types" do
          result = define_schema do |api|
            api.object_type "Person" do |t|
              t.field "id", "ID!"
              t.field "name", "String"
              t.field "age", "Int"
              t.field "nationality", "String", groupable: true
              t.index "people"
            end

            api.object_type "Company" do |t|
              t.implements "Inventor"
              t.field "id", "ID!"
              t.field "name", "String"
              t.field "age", "Int"
              t.field "stock_ticker", "String"
              t.index "companies"
            end

            api.interface_type "Inventor" do |t|
              t.field "name", "String"
            end
          end

          expect(connection_type_from(result, "Inventor")).to eq(<<~EOS.strip)
            type InventorConnection {
              #{schema_elements.edges}: [InventorEdge!]!
              #{schema_elements.nodes}: [Inventor!]!
              #{schema_elements.page_info}: PageInfo!
              #{schema_elements.total_edge_count}: JsonSafeLong!
            }
          EOS
        end

        it "defines `*Connection` types for each indexed aggregation type" do
          result = define_schema do |api|
            api.object_type "Widget" do |t|
              t.field "id", "ID!"
              t.field "int", "Int", aggregatable: true
              t.index "widgets"
            end
          end

          expect(aggregation_connection_type_from(result, "Widget", include_docs: true)).to eq(<<~EOS.strip)
            """
            Represents a paginated collection of `WidgetAggregation` results.

            See the [Relay GraphQL Cursor Connections
            Specification](https://relay.dev/graphql/connections.htm#sec-Connection-Types) for more info.
            """
            type WidgetAggregationConnection {
              """
              Wraps a specific `WidgetAggregation` to pair it with its pagination cursor.
              """
              #{schema_elements.edges}: [WidgetAggregationEdge!]!
              """
              The list of `WidgetAggregation` results.
              """
              #{schema_elements.nodes}: [WidgetAggregation!]!
              """
              Provides pagination-related information.
              """
              #{schema_elements.page_info}: PageInfo!
            }
          EOS
        end

        it "does not define Connection types for embedded union types" do
          result = define_schema do |api|
            api.object_type "Person" do |t|
              t.field "name", "String"
              t.field "age", "Int"
              t.field "nationality", "String"
            end

            api.object_type "Company" do |t|
              t.field "name", "String"
              t.field "age", "Int"
              t.field "stock_ticker", "String"
            end

            api.union_type "Inventor" do |t|
              t.subtypes "Person", "Company"
            end
          end

          expect(connection_type_from(result, "Inventor")).to eq(nil)
        end

        it "avoids defining an `aggregations` field on a Connection type when there is no `Aggregation` type" do
          result = define_schema do |api|
            api.object_type "Widget" do |t|
              t.field "id", "ID!", aggregatable: false, groupable: false
              t.index "widgets"
            end
          end

          expect(connection_type_from(result, "Widget")).to eq(<<~EOS.strip)
            type WidgetConnection {
              #{schema_elements.edges}: [WidgetEdge!]!
              #{schema_elements.nodes}: [Widget!]!
              #{schema_elements.page_info}: PageInfo!
              #{schema_elements.total_edge_count}: JsonSafeLong!
            }
          EOS
        end

        it "only defines `highlights` and `all_highlights` on `*Edge` types derived from indexed object types" do
          result = define_schema do |api|
            api.object_type "WidgetIndexed" do |t|
              t.field "id", "ID!"
              t.field "name", "String"
              t.paginated_collection_field "widgets_unindexed", "WidgetUnIndexed" do |f|
                f.mapping type: "object"
              end
              t.index "widgets"
            end

            api.object_type "WidgetUnIndexed" do |t|
              t.field "id", "ID!"
              t.field "name", "String"
            end
          end

          expect(edge_type_from(result, "WidgetIndexed")).to eq(<<~EOS.strip)
            type WidgetIndexedEdge {
              #{schema_elements.node}: WidgetIndexed
              #{schema_elements.cursor}: Cursor
              #{schema_elements.all_highlights}: [SearchHighlight!]!
              #{schema_elements.highlights}: WidgetIndexedHighlights
            }
          EOS

          expect(edge_type_from(result, "WidgetUnIndexed")).to eq(<<~EOS.strip)
            type WidgetUnIndexedEdge {
              #{schema_elements.node}: WidgetUnIndexed
              #{schema_elements.cursor}: Cursor
            }
          EOS
        end

        it "only defines `highlights` on an `*Edge` type if the source type has highlightable fields" do
          result = define_schema do |api|
            api.object_type "HighlightableWidget" do |t|
              t.field "id", "ID!", highlightable: true
              t.index "widgets"
            end

            api.object_type "UnhighlightableWidget" do |t|
              t.field "id", "ID!", highlightable: false
              t.index "widgets"
            end
          end

          expect(edge_type_from(result, "HighlightableWidget")).to eq(<<~EOS.strip)
            type HighlightableWidgetEdge {
              #{schema_elements.node}: HighlightableWidget
              #{schema_elements.cursor}: Cursor
              #{schema_elements.all_highlights}: [SearchHighlight!]!
              #{schema_elements.highlights}: HighlightableWidgetHighlights
            }
          EOS

          expect(edge_type_from(result, "UnhighlightableWidget")).to eq(<<~EOS.strip)
            type UnhighlightableWidgetEdge {
              #{schema_elements.node}: UnhighlightableWidget
              #{schema_elements.cursor}: Cursor
              #{schema_elements.all_highlights}: [SearchHighlight!]!
            }
          EOS
        end

        def aggregation_efficency_hint_for(result, query_field)
          query_def = type_def_from(result, "Query", include_docs: true)
          aggregations_comments = query_def[/(#{TestSupport::DOC_COMMENTS})\s*#{correctly_cased(query_field)}\(/, 1]
          aggregations_comments.split("\n").map { |l| l.delete_prefix("  ") }.join("\n")
        end
      end
    end
  end
end
