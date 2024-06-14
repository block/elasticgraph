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
    RSpec.describe "GraphQL schema generation", "an `*GroupedBy` type" do
      include_context "GraphQL schema spec support"

      with_both_casing_forms do
        it "includes a field for each groupable field" do
          results = define_schema do |schema|
            schema.object_type "Widget" do |t|
              t.field "id", "ID", groupable: true
              t.field "name", "String" do |f|
                f.documentation "The widget's name."
              end
              t.field "size", "String"
              t.field "cost", "Int", groupable: false
              t.index "widgets"
            end
          end

          expect(grouped_by_type_from(results, "Widget", include_docs: true)).to eq(<<~EOS.strip)
            """
            Type used to specify the `Widget` fields to group by for aggregations.
            """
            type WidgetGroupedBy {
              """
              The `id` field value for this group.
              """
              id: ID
              """
              The `name` field value for this group:

              > The widget's name.
              """
              name: String
              """
              The `size` field value for this group.
              """
              size: String
            }
          EOS
        end

        it "omits `id` on an indexed type by default since grouping on it would yield buckets of 1 document each" do
          results = define_schema do |schema|
            schema.object_type "Widget" do |t|
              t.field "id", "ID"
              t.field "name", "String"
              t.field "size", "String"
              t.index "widgets"
            end
          end

          expect(grouped_by_type_from(results, "Widget")).to eq(<<~EOS.strip)
            type WidgetGroupedBy {
              name: String
              size: String
            }
          EOS
        end

        it "includes `id` on a non-indexed type since it is not necessarily a unique primary key" do
          results = define_schema do |schema|
            schema.object_type "Widget" do |t|
              t.field "id", "ID"
              t.field "name", "String"
              t.field "size", "String"
            end
          end

          expect(grouped_by_type_from(results, "Widget")).to eq(<<~EOS.strip)
            type WidgetGroupedBy {
              id: ID
              name: String
              size: String
            }
          EOS
        end

        it "does not define grouped by field for a list or paginated collection field by default since it has odd semantics" do
          results = define_schema do |api|
            api.object_type "Widget" do |t|
              t.field "id", "ID!", groupable: false
              t.field "some_string", "String"
              t.field "some_string2", "[String!]"
              t.field "some_int", "Int"
              t.field "some_int2", "[Int]"
              t.field "some_float", "Float!"
              t.field "some_float2", "[Float!]"
              t.field "some_long", "JsonSafeLong"
              t.field "some_long2", "[JsonSafeLong!]!"
              t.paginated_collection_field "tags", "String"
              t.index "widgets"
            end
          end

          expect(grouped_by_type_from(results, "Widget")).to eq(<<~EOS.strip)
            type WidgetGroupedBy {
              some_string: String
              some_int: Int
              some_float: Float
              some_long: JsonSafeLong
            }
          EOS
        end

        it "allows a scalar list field to be grouped by specifying its `singular` name" do
          results = define_schema do |api|
            api.object_type "Widget" do |t|
              t.field "id", "ID!", groupable: false
              t.field "tags", "[String!]", singular: "tag"
              t.field "categories", "[String!]", singular: "category" do |f|
                f.documentation "The category of the widget."
              end
              t.index "widgets"
            end
          end

          expect(grouped_by_type_from(results, "Widget", include_docs: true)).to eq(<<~EOS.strip)
            """
            Type used to specify the `Widget` fields to group by for aggregations.
            """
            type WidgetGroupedBy {
              """
              The individual value from `tags` for this group.

              Note: `tags` is a collection field, but selecting this field will group on individual values of `tags`.
              That means that a document may be grouped into multiple aggregation groupings (i.e. when its `tags`
              field has multiple values) leading to some data duplication in the response. However, if a value shows
              up in `tags` multiple times for a single document, that document will only be included in the group
              once.
              """
              tag: String
              """
              The individual value from `categories` for this group:

              > The category of the widget.

              Note: `categories` is a collection field, but selecting this field will group on individual values of `categories`.
              That means that a document may be grouped into multiple aggregation groupings (i.e. when its `categories`
              field has multiple values) leading to some data duplication in the response. However, if a value shows
              up in `categories` multiple times for a single document, that document will only be included in the group
              once.
              """
              category: String
            }
          EOS
        end

        it "allows a paginated collection field to be grouped by specifying its `singular` name" do
          results = define_schema do |api|
            api.object_type "Widget" do |t|
              t.field "id", "ID!", groupable: false
              t.paginated_collection_field "tags", "String", singular: "tag"
              t.index "widgets"
            end
          end

          expect(grouped_by_type_from(results, "Widget", include_docs: true)).to eq(<<~EOS.strip)
            """
            Type used to specify the `Widget` fields to group by for aggregations.
            """
            type WidgetGroupedBy {
              """
              The individual value from `tags` for this group.

              Note: `tags` is a collection field, but selecting this field will group on individual values of `tags`.
              That means that a document may be grouped into multiple aggregation groupings (i.e. when its `tags`
              field has multiple values) leading to some data duplication in the response. However, if a value shows
              up in `tags` multiple times for a single document, that document will only be included in the group
              once.
              """
              tag: String
            }
          EOS
        end

        it "respects type name overrides when generating the `singular` grouping field for a paginated collection field" do
          results = define_schema(type_name_overrides: {LocalTime: "TimeOfDay"}) do |api|
            api.object_type "Widget" do |t|
              t.field "id", "ID!", groupable: false
              t.paginated_collection_field "times", "LocalTime", singular: "time"
              t.index "widgets"
            end
          end

          expect(grouped_by_type_from(results, "Widget")).to eq(<<~EOS.strip)
            type WidgetGroupedBy {
              time: TimeOfDay
            }
          EOS
        end

        it "allows a list-of-objects-of-scalars to be grouped on so the scalar subfields can be grouped on" do
          results = define_schema do |api|
            api.object_type "WidgetOptions" do |t|
              t.field "size", "Int"
            end

            api.object_type "Widget" do |t|
              t.field "id", "ID!"
              t.field "options", "[WidgetOptions!]!" do |f|
                f.mapping type: "object"
              end
              t.index "widgets"
            end
          end

          expect(grouped_by_type_from(results, "Widget", include_docs: true)).to eq(<<~EOS.strip)
            """
            Type used to specify the `Widget` fields to group by for aggregations.
            """
            type WidgetGroupedBy {
              """
              The `options` field value for this group.

              Note: `options` is a collection field, but selecting this field will group on individual values of the selected subfields of `options`.
              That means that a document may be grouped into multiple aggregation groupings (i.e. when its `options`
              field has multiple values) leading to some data duplication in the response. However, if a value shows
              up in `options` multiple times for a single document, that document will only be included in the group
              once.
              """
              options: WidgetOptionsGroupedBy
            }
          EOS

          expect(grouped_by_type_from(results, "WidgetOptions")).to eq(<<~EOS.strip)
            type WidgetOptionsGroupedBy {
              size: Int
            }
          EOS
        end

        it "makes a list-of-nested-objects field ungroupable since nested fields require special aggregation operations in the datastore query to work properly" do
          results = define_schema do |api|
            api.object_type "WidgetOptions" do |t|
              t.field "size", "Int"
            end

            api.object_type "Widget" do |t|
              t.field "id", "ID!"
              t.field "name", "String"
              t.field "options", "[WidgetOptions!]!" do |f|
                f.mapping type: "nested"
              end
              t.index "widgets"
            end
          end

          expect(grouped_by_type_from(results, "Widget")).to eq(<<~EOS.strip)
            type WidgetGroupedBy {
              name: String
            }
          EOS
        end

        it "does not generate the type if no fields are groupable" do
          results = define_schema do |schema|
            schema.object_type "Widget" do |t|
              t.field "id", "ID" # id is automatically not groupable, because it uniquely identifies each document!
              t.field "cost", "Int", groupable: false
              t.index "widgets"
            end
          end

          expect(grouped_by_type_from(results, "Widget")).to eq nil
        end

        it "references a nested `GroupedBy` type for embedded object fields" do
          results = define_schema do |schema|
            schema.object_type "Widget" do |t|
              t.field "id", "ID"
              t.field "name", "String"
              t.field "widget_options", "WidgetOptions"
              t.index "widgets"
            end

            schema.object_type "WidgetOptions" do |t|
              t.field "size", "String"
              t.field "color", "String"
            end
          end

          expect(grouped_by_type_from(results, "Widget")).to eq(<<~EOS.strip)
            type WidgetGroupedBy {
              name: String
              widget_options: WidgetOptionsGroupedBy
            }
          EOS

          expect(grouped_by_type_from(results, "WidgetOptions")).to eq(<<~EOS.strip)
            type WidgetOptionsGroupedBy {
              size: String
              color: String
            }
          EOS
        end

        it "defines grouping arguments for Date and DateTime fields with full documentation" do
          results = define_schema do |schema|
            schema.object_type "Widget" do |t|
              t.field "id", "ID", groupable: true
              t.field "created_on", "Date"
              t.field "created_at", "DateTime"
              t.index "widgets"
            end
          end

          expect(grouped_by_type_from(results, "Widget", include_docs: true)).to eq(<<~EOS.strip)
            """
            Type used to specify the `Widget` fields to group by for aggregations.
            """
            type WidgetGroupedBy {
              """
              The `id` field value for this group.
              """
              id: ID
              """
              Offers the different grouping options for the `created_on` value within this group.
              """
              created_on: DateGroupedBy
              """
              Offers the different grouping options for the `created_at` value within this group.
              """
              created_at: DateTimeGroupedBy
            }
          EOS
        end

        it "makes fields of all leaf types groupable except when it has a `text` mapping since that can't be grouped on efficiently" do
          results = define_schema do |schema|
            schema.enum_type "Color" do |t|
              t.values "RED", "GREEN", "YELLOW"
            end

            schema.object_type "Widget" do |t|
              t.field "id", "ID"
              t.field "name", "String!"
              t.field "workspace_id", "ID"
              t.field "size", "String!"
              t.field "cost", "Int!"
              t.field "cost_byte", "Int" do |f|
                f.mapping type: "byte"
              end
              t.field "cost_short", "Int" do |f|
                f.mapping type: "short"
              end
              t.field "cost_float", "Float!"
              t.field "cost_json_safe_long", "JsonSafeLong"
              t.field "cost_long_string", "LongString"
              t.field "metadata", "Untyped"
              t.field "zone", "TimeZone!"
              t.field "sold", "Boolean"
              t.field "color", "Color"
              t.field "created_on", "Date!"
              t.field "created_at", "DateTime"
              t.field "description", "String" do |f|
                f.mapping type: "text"
              end

              t.index "widgets"
            end
          end

          expect(grouped_by_type_from(results, "Widget")).to eq(<<~EOS.strip)
            type WidgetGroupedBy {
              name: String
              workspace_id: ID
              size: String
              cost: Int
              cost_byte: Int
              cost_short: Int
              cost_float: Float
              cost_json_safe_long: JsonSafeLong
              cost_long_string: LongString
              metadata: Untyped
              zone: TimeZone
              sold: Boolean
              color: Color
              created_on: DateGroupedBy
              created_at: DateTimeGroupedBy
            }
          EOS
        end

        it "does not make object fields with a custom mapping type groupable" do
          results = define_schema do |schema|
            schema.object_type "Point1" do |t|
              t.field "x", "Float"
              t.field "y", "Float"
              t.mapping type: "point"
            end

            schema.object_type "Point2" do |t|
              t.field "x", "Float"
              t.field "y", "Float"
            end

            schema.object_type "Widget" do |t|
              t.field "id", "ID"
              t.field "point1", "Point1"
              t.field "point2", "Point2"

              t.index "widgets"
            end
          end

          expect(grouped_by_type_from(results, "Widget")).to eq(<<~EOS.strip)
            type WidgetGroupedBy {
              point2: Point2GroupedBy
            }
          EOS

          expect(grouped_by_type_from(results, "Point1")).to eq(nil)

          expect(grouped_by_type_from(results, "Point2")).to eq(<<~EOS.strip)
            type Point2GroupedBy {
              x: Float
              y: Float
            }
          EOS
        end

        it "makes object fields with custom mapping options groupable so long as the `type` hasn't been customized" do
          results = define_schema do |schema|
            schema.object_type "Point" do |t|
              t.field "x", "Float"
              t.field "y", "Float"
              t.mapping meta: {defined_by: "ElasticGraph"}
            end

            schema.object_type "Widget" do |t|
              t.field "id", "ID"
              t.field "point", "Point"

              t.index "widgets"
            end
          end

          expect(grouped_by_type_from(results, "Widget")).to eq(<<~EOS.strip)
            type WidgetGroupedBy {
              point: PointGroupedBy
            }
          EOS

          expect(grouped_by_type_from(results, "Point")).to eq(<<~EOS.strip)
            type PointGroupedBy {
              x: Float
              y: Float
            }
          EOS
        end

        it "does not make relation fields groupable (but still makes a non-relation field of the same type groupable)" do
          results = define_schema do |schema|
            schema.object_type "Component" do |t|
              t.field "id", "ID"
              t.field "name", "String"

              t.index "components"
            end

            schema.object_type "Widget" do |t|
              t.field "id", "ID"
              t.relates_to_one "related_component", "Component", via: "component_id", dir: :out
              t.field "embedded_component", "Component"

              t.index "widgets"
            end
          end

          expect(grouped_by_type_from(results, "Widget")).to eq(<<~EOS.strip)
            type WidgetGroupedBy {
              embedded_component: ComponentGroupedBy
            }
          EOS
        end

        it "allows the grouped by fields to be customized" do
          result = define_schema do |api|
            api.raw_sdl "directive @external on FIELD_DEFINITION"

            api.object_type "WidgetOptions" do |t|
              t.field "color", "String"
            end

            api.object_type "Widget" do |t|
              t.field "name", "String" do |f|
                f.customize_grouped_by_field do |gbf|
                  gbf.directive "deprecated"
                end

                f.customize_grouped_by_field do |gbf|
                  gbf.directive "external"
                end
              end

              t.field "options", "WidgetOptions" do |f|
                f.customize_grouped_by_field do |gbf|
                  gbf.directive "deprecated"
                end
              end

              t.field "size", "Int" do |f|
                f.customize_grouped_by_field do |gbf|
                  gbf.directive "external"
                end
              end
            end
          end

          expect(grouped_by_type_from(result, "Widget")).to eq(<<~EOS.strip)
            type WidgetGroupedBy {
              name: String @deprecated @external
              options: WidgetOptionsGroupedBy @deprecated
              size: Int @external
            }
          EOS
        end

        shared_examples_for "a type with subtypes" do |type_def_method|
          it "defines a field for an abstract type if that abstract type has aggregatable fields" do
            results = define_schema do |api|
              api.object_type "Person" do |t|
                link_subtype_to_supertype(t, "Inventor")
                t.field "name", "String"
                t.field "age", "Int"
                t.field "nationality", "String"
              end

              api.object_type "Company" do |t|
                link_subtype_to_supertype(t, "Inventor")
                t.field "name", "String"
                t.field "age", "Int"
                t.field "stock_ticker", "String"
              end

              api.public_send type_def_method, "Inventor" do |t|
                link_supertype_to_subtypes(t, "Person", "Company")
              end

              api.object_type "Widget" do |t|
                t.field "id", "ID!"
                t.field "inventor", "Inventor"
                t.index "widgets"
              end
            end

            expect(grouped_by_type_from(results, "Widget")).to eq(<<~EOS.strip)
              type WidgetGroupedBy {
                inventor: InventorGroupedBy
              }
            EOS
          end

          it "defines the type using the set union of the fields of the subtypes" do
            result = define_schema do |api|
              api.object_type "Person" do |t|
                link_subtype_to_supertype(t, "Inventor")
                t.field "name", "String"
                t.field "age", "Int"
                t.field "nationality", "String"
              end

              api.object_type "Company" do |t|
                link_subtype_to_supertype(t, "Inventor")
                t.field "name", "String"
                t.field "age", "Int"
                t.field "stock_ticker", "String"
              end

              api.public_send type_def_method, "Inventor" do |t|
                link_supertype_to_subtypes(t, "Person", "Company")
              end
            end

            expect(grouped_by_type_from(result, "Inventor")).to eq(<<~EOS.strip)
              type InventorGroupedBy {
                name: String
                age: Int
                nationality: String
                stock_ticker: String
              }
            EOS
          end
        end

        context "on a type union" do
          include_examples "a type with subtypes", :union_type do
            def link_subtype_to_supertype(object_type, supertype_name)
              # nothing to do; the linkage happens via a `subtypes` call on the supertype
            end

            def link_supertype_to_subtypes(union_type, *subtype_names)
              union_type.subtypes(*subtype_names)
            end
          end
        end

        context "on an interface type" do
          include_examples "a type with subtypes", :interface_type do
            def link_subtype_to_supertype(object_type, interface_name)
              object_type.implements interface_name
            end

            def link_supertype_to_subtypes(interface_type, *subtype_names)
              # nothing to do; the linkage happens via an `implements` call on the subtype
            end
          end

          it "recursively resolves the union of fields, to support type hierarchies" do
            result = define_schema do |api|
              api.object_type "Person" do |t|
                t.implements "Human"
                t.field "age", "Int"
                t.field "income", "Float"
              end

              api.object_type "Company" do |t|
                t.implements "Organization"
                t.field "age", "Int"
                t.field "share_value", "Float"
              end

              api.interface_type "Human" do |t|
                t.implements "Inventor"
              end

              api.interface_type "Organization" do |t|
                t.implements "Inventor"
              end

              api.interface_type "Inventor" do |t|
              end
            end

            expect(grouped_by_type_from(result, "Inventor")).to eq(<<~EOS.strip)
              type InventorGroupedBy {
                age: Int
                income: Float
                share_value: Float
              }
            EOS
          end
        end
      end
    end
  end
end
