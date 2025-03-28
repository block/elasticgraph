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
    RSpec.describe "GraphQL schema generation", "#paginated_collection_field" do
      include_context "GraphQL schema spec support"

      with_both_casing_forms do
        it "defines the field as a `Connection` type" do
          result = define_schema do |api|
            api.object_type "Widget" do |t|
              t.paginated_collection_field "names", "String"
            end
          end

          expect(type_def_from(result, "Widget")).to eq(<<~EOS.chomp)
            type Widget {
              names(
                first: Int
                after: Cursor
                last: Int
                before: Cursor): StringConnection
            }
          EOS
        end

        it "causes the `Connection` type of the provided element type to be generated" do
          result = define_schema do |api|
            api.object_type "Widget" do |t|
              t.field "id", "ID!"
              t.paginated_collection_field "names", "String"
              t.index "widgets"
            end
          end

          expect(connection_type_from(result, "String")).to eq(<<~EOS.chomp)
            type StringConnection {
              #{schema_elements.edges}: [StringEdge!]!
              #{schema_elements.nodes}: [String!]!
              #{schema_elements.page_info}: PageInfo!
              #{schema_elements.total_edge_count}: JsonSafeLong!
            }
          EOS
        end

        it "causes the `Edge` type of the provided element type to be generated" do
          result = define_schema do |api|
            api.object_type "Widget" do |t|
              t.paginated_collection_field "names", "String"
            end
          end

          expect(edge_type_from(result, "String")).to eq(<<~EOS.chomp)
            type StringEdge {
              node: String
              cursor: Cursor
            }
          EOS
        end

        it "supports collections of objects in addition to scalars" do
          result = define_schema do |api|
            api.object_type "WidgetOptions" do |t|
              t.field "size", "Int"
            end

            api.object_type "Widget" do |t|
              t.field "id", "ID"
              t.paginated_collection_field "optionses", "WidgetOptions" do |f|
                f.mapping type: "object"
              end
              t.index "widgets"
            end
          end

          expect(type_def_from(result, "Widget")).to eq(<<~EOS.chomp)
            type Widget {
              id: ID
              optionses(
                first: Int
                after: Cursor
                last: Int
                before: Cursor): WidgetOptionsConnection
            }
          EOS

          expect(connection_type_from(result, "WidgetOptions")).to eq(<<~EOS.chomp)
            type WidgetOptionsConnection {
              #{schema_elements.edges}: [WidgetOptionsEdge!]!
              #{schema_elements.nodes}: [WidgetOptions!]!
              #{schema_elements.page_info}: PageInfo!
              #{schema_elements.total_edge_count}: JsonSafeLong!
            }
          EOS

          expect(edge_type_from(result, "WidgetOptions")).to eq(<<~EOS.chomp)
            type WidgetOptionsEdge {
              node: WidgetOptions
              cursor: Cursor
            }
          EOS
        end

        it "avoids referencing a `*ConnectionFilterInput` type that won't exist when defining the corresponding filter type, and avoids defining the pagination args on the filter's field" do
          result = define_schema do |api|
            api.object_type "Widget" do |t|
              t.paginated_collection_field "names", "String"
            end
          end

          expect(filter_type_from(result, "Widget")).to eq(<<~EOS.chomp)
            input WidgetFilterInput {
              #{schema_elements.any_of}: [WidgetFilterInput!]
              #{schema_elements.all_of}: [WidgetFilterInput!]
              #{schema_elements.not}: WidgetFilterInput
              names: StringListFilterInput
            }
          EOS
        end

        it "respects a type name override used for the type passed to `paginated_collection_field`" do
          result = define_schema(type_name_overrides: {LocalTime: "TimeOfDay"}) do |api|
            api.object_type "Widget" do |t|
              t.paginated_collection_field "times", "LocalTime"
            end
          end

          expect(type_def_from(result, "Widget")).to eq(<<~EOS.chomp)
            type Widget {
              times(
                #{schema_elements.first}: Int
                #{schema_elements.after}: Cursor
                #{schema_elements.last}: Int
                #{schema_elements.before}: Cursor): TimeOfDayConnection
            }
          EOS

          expect(connection_type_from(result, "TimeOfDay")).to eq(<<~EOS.chomp)
            type TimeOfDayConnection {
              #{schema_elements.edges}: [TimeOfDayEdge!]!
              #{schema_elements.nodes}: [TimeOfDay!]!
              #{schema_elements.page_info}: PageInfo!
              #{schema_elements.total_edge_count}: JsonSafeLong!
            }
          EOS

          expect(edge_type_from(result, "TimeOfDay")).to eq(<<~EOS.chomp)
            type TimeOfDayEdge {
              #{schema_elements.node}: TimeOfDay
              #{schema_elements.cursor}: Cursor
            }
          EOS

          expect(filter_type_from(result, "Widget")).to eq(<<~EOS.chomp)
            input WidgetFilterInput {
              #{schema_elements.any_of}: [WidgetFilterInput!]
              #{schema_elements.all_of}: [WidgetFilterInput!]
              #{schema_elements.not}: WidgetFilterInput
              times: TimeOfDayListFilterInput
            }
          EOS
        end

        it "avoids generating a sort order enum value for the field, just as it would for a list field" do
          result = define_schema do |api|
            api.object_type "Widget" do |t|
              t.field "id", "ID!"
              t.paginated_collection_field "names", "String"
              t.index "widgets"
            end
          end

          expect(sort_order_type_from(result, "Widget")).to eq(<<~EOS.chomp)
            enum WidgetSortOrderInput {
              id_ASC
              id_DESC
            }
          EOS
        end

        it "allows the field to be documented just like with `.field`" do
          result = define_schema do |api|
            api.object_type "Widget" do |t|
              t.paginated_collection_field "names", "String" do |f|
                f.documentation "Paginated names."
              end
            end
          end

          expect(type_def_from(result, "Widget", include_docs: true)).to eq(<<~EOS.chomp)
            type Widget {
              """
              Paginated names.
              """
              names(
                """
                Used in conjunction with the `after` argument to forward-paginate through the `names`.
                When provided, limits the number of returned results to the first `n` after the provided
                `after` cursor (or from the start of the `names`, if no `after` cursor is provided).

                See the [Relay GraphQL Cursor Connections
                Specification](https://relay.dev/graphql/connections.htm#sec-Arguments) for more info.
                """
                first: Int
                """
                Used to forward-paginate through the `names`. When provided, the next page after the
                provided cursor will be returned.

                See the [Relay GraphQL Cursor Connections
                Specification](https://relay.dev/graphql/connections.htm#sec-Arguments) for more info.
                """
                after: Cursor
                """
                Used in conjunction with the `before` argument to backward-paginate through the `names`.
                When provided, limits the number of returned results to the last `n` before the provided
                `before` cursor (or from the end of the `names`, if no `before` cursor is provided).

                See the [Relay GraphQL Cursor Connections
                Specification](https://relay.dev/graphql/connections.htm#sec-Arguments) for more info.
                """
                last: Int
                """
                Used to backward-paginate through the `names`. When provided, the previous page before the
                provided cursor will be returned.

                See the [Relay GraphQL Cursor Connections
                Specification](https://relay.dev/graphql/connections.htm#sec-Arguments) for more info.
                """
                before: Cursor): StringConnection
            }
          EOS
        end
      end
    end
  end
end
