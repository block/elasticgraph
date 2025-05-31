# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require_relative "graphql_schema_spec_support"

module ElasticGraph
  module SchemaDefinition
    RSpec.describe "GraphQL schema generation", "derived graphql type customizations" do
      include_context "GraphQL schema spec support"

      with_both_casing_forms do
        it "allows `customize_derived_types` to be used to customize specific types derived from indexed types" do
          result = define_schema do |api|
            api.raw_sdl "directive @external on OBJECT | INPUT_OBJECT | ENUM"
            api.raw_sdl "directive @derived on OBJECT | INPUT_OBJECT | ENUM"

            api.object_type "Widget" do |t|
              t.field "id", "ID!"
              t.field "name", "String"
              t.field "cost", "Int"
              # Some derived types are only generated when a type has nested fields.
              t.field "is_nested", "[IsNested!]!" do |f|
                f.mapping type: "nested"
              end
              t.index "widgets"

              # Here we are trying to exhaustively cover all possible derived graphql types to ensure that our "invalid derived graphql type" detection
              # doesn't wrongly consider any of these to be invalid.
              t.customize_derived_types(
                "WidgetConnection", "WidgetAggregatedValues", "WidgetGroupedBy",
                "WidgetAggregation", "WidgetAggregationEdge", "WidgetAggregationConnection",
                "HasNestedWidgetSubAggregation", "HasNestedWidgetSubAggregationConnection",
                "HasNestedWidgetSubAggregationSubAggregations", "WidgetAggregationSubAggregations"
              ) do |dt|
                dt.directive "deprecated"
              end

              t.customize_derived_types "WidgetAggregation", "WidgetEdge", "WidgetFilterInput", "WidgetListFilterInput", "WidgetFieldsListFilterInput", "WidgetHighlights", "WidgetSortOrderInput" do |dt|
                dt.directive "external"
              end

              t.customize_derived_types :all do |dt|
                dt.directive "derived"
              end
            end

            api.object_type "IsNested" do |t|
              t.field "something", "String"
            end

            api.object_type "HasNested" do |t|
              t.field "id", "ID"
              # Some derived types are only generated when a type is used by a nested field.
              t.field "widgets", "[Widget!]!" do |f|
                f.mapping type: "nested"
              end
              t.index "has_nested"
            end
          end

          expect(type_def_from(result, "Widget")).not_to include("@deprecated", "@external", "@derived")

          expect(connection_type_from(result, "Widget")).to include("WidgetConnection @deprecated @derived {")
          expect(aggregated_values_type_from(result, "Widget")).to include("WidgetAggregatedValues @deprecated @derived {")
          expect(grouped_by_type_from(result, "Widget")).to include("WidgetGroupedBy @deprecated @derived {")
          expect(edge_type_from(result, "Widget")).to include("WidgetEdge @external @derived {")
          expect(filter_type_from(result, "Widget")).to include("WidgetFilterInput @external @derived {")
          expect(highlights_type_from(result, "Widget")).to include("WidgetHighlights @external @derived {")
          expect(list_filter_type_from(result, "Widget")).to include("WidgetListFilterInput @external @derived {")
          expect(fields_list_filter_type_from(result, "Widget")).to include("WidgetFieldsListFilterInput @external @derived {")
          expect(sort_order_type_from(result, "Widget")).to include("WidgetSortOrderInput @external @derived {")
          expect(aggregation_type_from(result, "Widget")).to include("WidgetAggregation @deprecated @external @derived {")
          expect(aggregation_connection_type_from(result, "Widget")).to include("WidgetAggregationConnection @deprecated @derived {")
          expect(aggregation_edge_type_from(result, "Widget")).to include("WidgetAggregationEdge @deprecated @derived {")

          expect(sub_aggregation_type_from(result, "HasNestedWidget")).to include("HasNestedWidgetSubAggregation @deprecated @derived {")
          expect(sub_aggregation_connection_type_from(result, "HasNestedWidget")).to include("HasNestedWidgetSubAggregationConnection @deprecated @derived {")
          expect(sub_aggregation_sub_aggregations_type_from(result, "HasNestedWidget")).to include("HasNestedWidgetSubAggregationSubAggregations @deprecated @derived {")
          expect(aggregation_sub_aggregations_type_from(result, "Widget")).to include("WidgetAggregationSubAggregations @deprecated @derived {")
        end

        it "respects `customize_derived_types` with every derived graphql type" do
          known_derived_graphql_type_names = %w[
            WidgetAggregatedValues
            WidgetGroupedBy
            WidgetAggregation
            WidgetAggregationConnection
            WidgetAggregationEdge
            WidgetConnection
            WidgetEdge
            WidgetFilterInput
            WidgetHighlights
            WidgetListFilterInput
            WidgetFieldsListFilterInput
            WidgetSortOrderInput
            HasNestedWidgetSubAggregation
            HasNestedWidgetSubAggregationConnection
            HasNestedWidgetSubAggregationSubAggregations
            WidgetAggregationSubAggregations
          ]

          result = define_schema do |api|
            api.object_type "Widget" do |t|
              t.field "id", "ID!"
              t.field "name", "String"
              t.field "cost", "Int"
              t.index "widgets"

              # Some derived types are only generated when a type has nested fields.
              t.field "is_nested", "[IsNested!]!" do |f|
                f.mapping type: "nested"
              end

              t.customize_derived_types(*known_derived_graphql_type_names) do |dt|
                dt.directive "deprecated"
              end
            end

            api.object_type "IsNested" do |t|
              t.field "something", "String"
            end

            api.object_type "HasNested" do |t|
              t.field "id", "ID"
              # Some derived types are only generated when a type is used by a nested field.
              t.field "widgets", "[Widget!]!" do |f|
                f.mapping type: "nested"
              end
              t.index "has_nested"
            end
          end

          all_widget_type_names = (
            result.scan(/(?:type|input|enum|union|interface|scalar) (\w*Widget[^\s]+)/).flatten -
            # These types are derived from the `IsNested` type, not from `Widget`, so they should not be impacted or covered here.
            %w[WidgetIsNestedSubAggregation WidgetIsNestedSubAggregationConnection HasNestedWidgetIsNestedSubAggregation HasNestedWidgetIsNestedSubAggregationConnection]
          )
          expect(all_widget_type_names).to match_array(known_derived_graphql_type_names),
            "This test is meant to cover all derived graphql types but is missing some. Please update the test to include them: " \
            "#{all_widget_type_names - known_derived_graphql_type_names}"

          expect(connection_type_from(result, "Widget")).to include("WidgetConnection @deprecated")
          expect(aggregated_values_type_from(result, "Widget")).to include("WidgetAggregatedValues @deprecated")
          expect(grouped_by_type_from(result, "Widget")).to include("WidgetGroupedBy @deprecated")
          expect(filter_type_from(result, "Widget")).to include("WidgetFilterInput @deprecated")
          expect(highlights_type_from(result, "Widget")).to include("WidgetHighlights @deprecated")
          expect(list_filter_type_from(result, "Widget")).to include("WidgetListFilterInput @deprecated")
          expect(fields_list_filter_type_from(result, "Widget")).to include("WidgetFieldsListFilterInput @deprecated")
          expect(edge_type_from(result, "Widget")).to include("WidgetEdge @deprecated")
          expect(sort_order_type_from(result, "Widget")).to include("WidgetSortOrderInput @deprecated")
          expect(aggregation_type_from(result, "Widget")).to include("WidgetAggregation @deprecated")
          expect(aggregation_connection_type_from(result, "Widget")).to include("WidgetAggregationConnection @deprecated")
          expect(aggregation_edge_type_from(result, "Widget")).to include("WidgetAggregationEdge @deprecated")

          expect(sub_aggregation_type_from(result, "HasNestedWidget")).to include("HasNestedWidgetSubAggregation @deprecated")
          expect(sub_aggregation_connection_type_from(result, "HasNestedWidget")).to include("HasNestedWidgetSubAggregationConnection @deprecated")
          expect(sub_aggregation_sub_aggregations_type_from(result, "HasNestedWidget")).to include("HasNestedWidgetSubAggregationSubAggregations @deprecated")
          expect(aggregation_sub_aggregations_type_from(result, "Widget")).to include("WidgetAggregationSubAggregations @deprecated")

          expect(type_def_from(result, "Widget")).not_to include("@deprecated")
        end

        it "allows `customize_derived_types` to be used on relay types generated for paginated collection fields" do
          result = define_schema do |api|
            api.raw_sdl "directive @external on OBJECT"

            api.scalar_type "Url" do |t|
              t.json_schema type: "string"
              t.mapping type: "keyword"

              t.customize_derived_types "UrlEdge", "UrlConnection" do |dt|
                dt.directive "external"
              end
            end

            api.object_type "Business" do |t|
              t.field "id", "ID"
              t.paginated_collection_field "urls", "Url"
              t.index "businesses"
            end
          end

          expect(connection_type_from(result, "Url")).to start_with "type UrlConnection @external {"
          expect(edge_type_from(result, "Url")).to start_with "type UrlEdge @external {"
        end

        it "allows `customize_derived_type_fields` to be used to customize specific fields on a specific derived graphql type" do
          result = define_schema do |api|
            api.raw_sdl "directive @external on FIELD_DEFINITION"
            api.raw_sdl "directive @internal on FIELD_DEFINITION"

            api.object_type "Widget" do |t|
              t.field "id", "ID!"
              t.field "cost", "Int"
              t.index "widgets"

              # Some derived types are only generated when a type has nested fields.
              t.field "is_nested1", "[IsNested!]!" do |f|
                f.mapping type: "nested"
              end

              t.field "is_nested2", "[IsNested!]!" do |f|
                f.mapping type: "nested"
              end

              t.customize_derived_type_fields "WidgetConnection", schema_elements.edges, schema_elements.page_info do |dt|
                dt.directive "internal"
              end

              t.customize_derived_type_fields "WidgetConnection", schema_elements.edges, schema_elements.nodes, schema_elements.total_edge_count do |dt|
                dt.directive "external"
              end

              t.customize_derived_type_fields "WidgetAggregationSubAggregations", "is_nested2" do |dt|
                dt.directive "external"
              end
            end

            api.object_type "IsNested" do |t|
              t.field "something", "String"
            end

            api.object_type "HasNested" do |t|
              t.field "id", "ID"
              # Some derived types are only generated when a type is used by a nested field.
              t.field "widgets", "[Widget!]!" do |f|
                f.mapping type: "nested"
              end
              t.index "has_nested"
            end
          end

          expect(connection_type_from(result, "Widget")).to eq(<<~EOS.strip)
            type WidgetConnection {
              edges: [WidgetEdge!]! @internal @external
              nodes: [Widget!]! @external
              #{schema_elements.page_info}: PageInfo! @internal
              #{schema_elements.total_edge_count}: JsonSafeLong! @external
            }
          EOS

          expect(type_def_from(result, "Widget")).not_to include("@internal")
          expect(filter_type_from(result, "Widget")).not_to include("@internal")
          expect(highlights_type_from(result, "Widget")).not_to include("@internal")
          expect(list_filter_type_from(result, "Widget")).not_to include("@internal")
          expect(fields_list_filter_type_from(result, "Widget")).not_to include("@internal")
          expect(edge_type_from(result, "Widget")).not_to include("@internal")
          expect(sort_order_type_from(result, "Widget")).not_to include("@internal")
          expect(aggregated_values_type_from(result, "Widget")).not_to include("@internal")
          expect(aggregation_type_from(result, "Widget")).not_to include("@internal")
          expect(aggregation_connection_type_from(result, "Widget")).not_to include("@internal")
          expect(aggregation_edge_type_from(result, "Widget")).not_to include("@internal")

          expect(sub_aggregation_type_from(result, "HasNestedWidget")).not_to include("@internal")
          expect(sub_aggregation_connection_type_from(result, "HasNestedWidget")).not_to include("@internal")
          expect(sub_aggregation_sub_aggregations_type_from(result, "HasNestedWidget")).not_to include("@internal")
          expect(aggregation_sub_aggregations_type_from(result, "Widget")).to eq(<<~EOS.strip)
            type WidgetAggregationSubAggregations {
              is_nested1(
                #{schema_elements.filter}: IsNestedFilterInput
                #{schema_elements.first}: Int): WidgetIsNestedSubAggregationConnection
              is_nested2(
                #{schema_elements.filter}: IsNestedFilterInput
                #{schema_elements.first}: Int): WidgetIsNestedSubAggregationConnection @external
            }
          EOS
        end

        it "notifies the user of an invalid derived graphql type name passed to `customize_derived_types`" do
          expect {
            define_schema do |api|
              api.object_type "Widget" do |t|
                t.field "id", "ID!"
                t.field "name", "String"
                t.index "widgets"

                # WidgetConnection is misspelled.
                t.customize_derived_types("WidgetConection", "WidgetGroupedBy") {}
              end
            end
          }.to raise_error Errors::SchemaError, a_string_including("customize_derived_types", "WidgetConection")
        end

        it "does not consider a valid derived graphql type suffix passed to `customize_derived_types` to be valid" do
          expect {
            define_schema do |api|
              api.object_type "Widget" do |t|
                t.field "id", "ID!"
                t.field "name", "String"
                t.index "widgets"

                # The derived graphql type is `WidgetConnection`, not `Connection`
                t.customize_derived_types("Connection") {}
              end
            end
          }.to raise_error Errors::SchemaError, a_string_including("customize_derived_types", "Connection")
        end

        it "notifies the user of a derived graphql type passed to `customize_derived_types` that winds up not existing but could exist if the type was defined differently" do
          expect {
            define_schema do |api|
              api.object_type "Widget" do |t|
                t.field "id", "ID!", groupable: false
                t.field "name", "String"

                t.customize_derived_types("WidgetFilterInput", "WidgetConnection", "WidgetEdge") {}
              end
            end
          }.to raise_error Errors::SchemaError, a_string_including("customize_derived_types", "WidgetConnection", "WidgetEdge").and(excluding("WidgetFilterInput"))
        end

        it "notifies the user of an invalid derived graphql type name passed to `customize_derived_type_fields`" do
          expect {
            define_schema do |api|
              api.object_type "Widget" do |t|
                t.field "id", "ID!"
                t.field "name", "String"
                t.index "widgets"

                # WidgetConnection is misspelled.
                t.customize_derived_type_fields("WidgetConection", "edges") {}
              end
            end
          }.to raise_error Errors::SchemaError, a_string_including("customize_derived_type_fields", "WidgetConection")
        end

        it "does not consider a valid derived graphql type suffix passed to `customize_derived_type_fields` to be valid" do
          expect {
            define_schema do |api|
              api.object_type "Widget" do |t|
                t.field "id", "ID!"
                t.field "name", "String"
                t.index "widgets"

                # The derived graphql type is `WidgetConnection`, not `Connection`
                t.customize_derived_type_fields("Connection", "edges") {}
              end
            end
          }.to raise_error Errors::SchemaError, a_string_including("customize_derived_type_fields", "Connection")
        end

        it "notifies the user of a derived graphql type passed to `customize_derived_type_fields` that winds up not existing but could exist if the type was defined differently" do
          expect {
            define_schema do |api|
              api.object_type "Widget" do |t|
                t.field "id", "ID!"
                t.field "name", "String"

                t.customize_derived_type_fields("WidgetConnection", "edges") {}
              end
            end
          }.to raise_error Errors::SchemaError, a_string_including("customize_derived_type_fields", "WidgetConnection")
        end

        it "notifies the user of an invalid derived field name passed to `customize_derived_type_fields`" do
          expect {
            define_schema do |api|
              api.object_type "Widget" do |t|
                t.field "id", "ID!"
                t.field "name", "String"
                t.index "widgets"

                # edge is misspelled (missing an `s`).
                t.customize_derived_type_fields("WidgetConnection", "edge") {}
              end
            end
          }.to raise_error Errors::SchemaError, a_string_including("customize_derived_type_fields", "WidgetConnection", "edge")
        end

        it "notifies the user if `customize_derived_type_fields` is used with a type that has no fields (e.g. an Enum type)" do
          expect {
            define_schema do |api|
              api.object_type "Widget" do |t|
                t.field "id", "ID!"
                t.field "name", "String"
                t.index "widgets"

                t.customize_derived_type_fields("WidgetSortOrderInput", "edges") {}
              end
            end
          }.to raise_error Errors::SchemaError, a_string_including("customize_derived_type_fields", "WidgetSortOrderInput")
        end
      end
    end
  end
end
