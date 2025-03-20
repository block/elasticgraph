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
    RSpec.describe "GraphQL schema generation", "sort order enum types" do
      include_context "GraphQL schema spec support"

      with_both_casing_forms do
        it "defines ASC and DESC enum values for each scalar field (boolean, and text fields) for each indexed type" do
          result = define_schema do |api|
            # demonstrate that it doesn't try to query the `Color` type for its subfields even though
            # it's a type defined via our type definition API.
            api.enum_type "Color" do |e|
              e.values "RED", "GREEN", "BLUE"
            end

            api.object_type "Widget" do |t|
              t.field "id", "ID!"
              t.field "another_id", "ID"
              t.field "some_string", "String"
              t.field "some_int", "Int!"
              t.field "some_ints", "[Int]"
              t.field "some_ints2", "[Int!]"
              t.field "some_ints3", "[Int]!"
              t.field "some_ints4", "[Int!]!"
              t.field "some_float", "Float"
              t.field "some_date", "Date"
              t.field "some_date_time", "DateTime!"
              t.field "color", "Color"
              t.field "some_boolean", "Boolean"
              t.field "another_boolean", "Boolean!"
              t.field "some_text", "String" do |f|
                f.mapping type: "text"
              end
              t.relates_to_one "parent", "Widget", via: "parent_id", dir: :out
              t.relates_to_many "children", "Widget", via: "children_ids", dir: :in, singular: "child"
              t.index "widgets"
            end
          end

          expect(sort_order_type_from(result, "Widget", include_docs: true)).to eq(<<~EOS.strip)
            """
            Enumerates the ways `Widget`s can be sorted.
            """
            enum WidgetSortOrderInput {
              """
              Sorts ascending by the `id` field.
              """
              id_ASC
              """
              Sorts descending by the `id` field.
              """
              id_DESC
              """
              Sorts ascending by the `another_id` field.
              """
              another_id_ASC
              """
              Sorts descending by the `another_id` field.
              """
              another_id_DESC
              """
              Sorts ascending by the `some_string` field.
              """
              some_string_ASC
              """
              Sorts descending by the `some_string` field.
              """
              some_string_DESC
              """
              Sorts ascending by the `some_int` field.
              """
              some_int_ASC
              """
              Sorts descending by the `some_int` field.
              """
              some_int_DESC
              """
              Sorts ascending by the `some_float` field.
              """
              some_float_ASC
              """
              Sorts descending by the `some_float` field.
              """
              some_float_DESC
              """
              Sorts ascending by the `some_date` field.
              """
              some_date_ASC
              """
              Sorts descending by the `some_date` field.
              """
              some_date_DESC
              """
              Sorts ascending by the `some_date_time` field.
              """
              some_date_time_ASC
              """
              Sorts descending by the `some_date_time` field.
              """
              some_date_time_DESC
              """
              Sorts ascending by the `color` field.
              """
              color_ASC
              """
              Sorts descending by the `color` field.
              """
              color_DESC
            }
          EOS
        end

        it "allows the sortability of a field to be set explicitly" do
          result = define_schema do |api|
            api.object_type "Widget" do |t|
              t.field "id", "ID!", sortable: false
              t.field "another_id", "ID", sortable: true
              t.field "some_string", "String", sortable: true
              t.field "some_int", "Int!", sortable: false
              t.field "some_float", "Float"
              t.index "widgets"
            end
          end

          expect(sort_order_type_from(result, "Widget")).to eq(<<~EOS.strip)
            enum WidgetSortOrderInput {
              another_id_ASC
              another_id_DESC
              some_string_ASC
              some_string_DESC
              some_float_ASC
              some_float_DESC
            }
          EOS
        end

        it "defines enum values for scalar fields of singleton embedded object types" do
          result = define_schema do |api|
            api.object_type "Color" do |t|
              t.field "red", "Int!"
              t.field "green", "Int!", name_in_index: "grn"
              t.field "blue", "Int!"
            end

            api.object_type "WidgetOptions" do |t|
              t.field "the_size", "Int"
              t.field "the_color", "Color", name_in_index: "clr"
              t.field "some_id", "ID"
              t.field "colors", "[Color]" do |f|
                f.mapping type: "object"
              end
            end

            api.object_type "Widget" do |t|
              t.field "id", "ID!"
              t.field "the_options", "WidgetOptions"
              t.field "options_array", "[WidgetOptions]" do |f|
                f.mapping type: "object"
              end
              t.field "some_float", "Float"
              t.index "widgets"
            end
          end

          expect(sort_order_type_from(result, "Widget")).to eq(<<~EOS.strip)
            enum WidgetSortOrderInput {
              id_ASC
              id_DESC
              the_options_the_size_ASC
              the_options_the_size_DESC
              the_options_the_color_red_ASC
              the_options_the_color_red_DESC
              the_options_the_color_green_ASC
              the_options_the_color_green_DESC
              the_options_the_color_blue_ASC
              the_options_the_color_blue_DESC
              the_options_some_id_ASC
              the_options_some_id_DESC
              some_float_ASC
              some_float_DESC
            }
          EOS
        end

        it "allows the derived enum values to be customized" do
          enum_field_paths = []

          result = define_schema do |api|
            api.raw_sdl "directive @external on ENUM_VALUE"

            api.object_type "WidgetOptions" do |t|
              t.field "the_size", "Int"
              t.field "some_id", "ID" do |f|
                f.customize_sort_order_enum_values do |v|
                  enum_field_paths << v.sort_order_field_path
                  v.directive "external"
                end
              end
            end

            api.object_type "Widget" do |t|
              t.field "id", "ID!"
              t.field "the_options", "WidgetOptions" do |f|
                f.customize_sort_order_enum_values do |v|
                  enum_field_paths << v.sort_order_field_path
                  v.directive "deprecated"
                end
              end

              t.field "some_float", "Float" do |f|
                f.customize_sort_order_enum_values do |v|
                  enum_field_paths << v.sort_order_field_path
                  v.directive "deprecated"
                end

                f.customize_sort_order_enum_values do |v|
                  enum_field_paths << v.sort_order_field_path
                  v.directive "external"
                end
              end

              t.index "widgets"
            end
          end

          expect(sort_order_type_from(result, "Widget")).to eq(<<~EOS.strip)
            enum WidgetSortOrderInput {
              id_ASC
              id_DESC
              the_options_the_size_ASC @deprecated
              the_options_the_size_DESC @deprecated
              the_options_some_id_ASC @deprecated @external
              the_options_some_id_DESC @deprecated @external
              some_float_ASC @deprecated @external
              some_float_DESC @deprecated @external
            }
          EOS

          expect(enum_field_paths.flatten).to all be_a(SchemaElements::Field)
          expect(enum_field_paths.map { |p| p.map(&:name).join(".") }).to match_array(
            # this field has 1 directive for ASC, 1 for DESC = 2 total
            (["the_options.the_size"] * 2) +
            # this field has 2 directives for ASC, 2 for DESC = 4 total
            (["the_options.some_id"] * 4) +
            # this field has 2 directives for ASC, 2 for DESC = 4 total
            (["some_float"] * 4)
          )
        end

        it "generates the `SortOrderInput` type for the `id` field even if no other fields are sortable" do
          result = define_schema do |api|
            api.object_type "Widget" do |t|
              t.field "id", "ID!"
              t.index "widgets"
            end
          end

          expect(sort_order_type_from(result, "Widget")).to eq(<<~EOS.strip)
            enum WidgetSortOrderInput {
              id_ASC
              id_DESC
            }
          EOS
        end

        it "does not define enum values for object fields that have a custom mapping type since we do not know if we can sort by the custom mapping" do
          result = define_schema do |api|
            api.object_type "Point" do |t|
              t.field "x", "Float"
              t.field "y", "Float"
              t.mapping type: "point"
            end

            api.object_type "Point2" do |t|
              t.field "x", "Float"
              t.field "y", "Float"
            end

            api.object_type "Widget" do |t|
              t.field "id", "ID!"
              t.field "nullable_point", "Point"
              t.field "non_null_point", "Point!"
              t.field "nullable_point2", "Point2"
              t.field "non_null_point2", "Point2!"
              t.index "widgets"
            end
          end

          expect(sort_order_type_from(result, "Widget")).to eq(<<~EOS.strip)
            enum WidgetSortOrderInput {
              id_ASC
              id_DESC
              nullable_point2_x_ASC
              nullable_point2_x_DESC
              nullable_point2_y_ASC
              nullable_point2_y_DESC
              non_null_point2_x_ASC
              non_null_point2_x_DESC
              non_null_point2_y_ASC
              non_null_point2_y_DESC
            }
          EOS
        end

        it "makes object fields with custom mapping options sortable so long as the `type` hasn't been customized" do
          result = define_schema do |api|
            api.object_type "Point" do |t|
              t.field "x", "Float"
              t.field "y", "Float"
              t.mapping meta: {defined_by: "ElasticGraph"}
            end

            api.object_type "Widget" do |t|
              t.field "id", "ID!"
              t.field "nullable_point", "Point"
              t.field "non_null_point", "Point!"
              t.index "widgets"
            end
          end

          expect(sort_order_type_from(result, "Widget")).to eq(<<~EOS.strip)
            enum WidgetSortOrderInput {
              id_ASC
              id_DESC
              nullable_point_x_ASC
              nullable_point_x_DESC
              nullable_point_y_ASC
              nullable_point_y_DESC
              non_null_point_x_ASC
              non_null_point_x_DESC
              non_null_point_y_ASC
              non_null_point_y_DESC
            }
          EOS
        end

        shared_examples_for "a type with subtypes" do |type_def_method|
          it "is generated for a directly indexed type" do
            result = define_schema do |api|
              api.object_type "Person" do |t|
                link_subtype_to_supertype(t, "Inventor")
                t.field "id", "ID!"
                t.field "name", "String"
                t.field "age", "Int"
                t.field "nationality", "String"
                t.index "people"
              end

              api.object_type "Company" do |t|
                link_subtype_to_supertype(t, "Inventor")
                t.field "id", "ID!"
                t.field "name", "String"
                t.field "age", "Int"
                t.field "stock_ticker", "String"
                t.index "companies"
              end

              api.public_send type_def_method, "Inventor" do |t|
                link_supertype_to_subtypes(t, "Person", "Company")
              end
            end

            expect(sort_order_type_from(result, "Inventor")).to eq(<<~EOS.strip)
              enum InventorSortOrderInput {
                id_ASC
                id_DESC
                name_ASC
                name_DESC
                age_ASC
                age_DESC
                nationality_ASC
                nationality_DESC
                stock_ticker_ASC
                stock_ticker_DESC
              }
            EOS
          end

          it "is not generated for an embedded type" do
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

            expect(sort_order_type_from(result, "Inventor")).to eq nil
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
        end

        it "recursively resolves the union of fields, to support type hierarchies" do
          result = define_schema do |api|
            api.object_type "Person" do |t|
              t.implements "Human"
              t.field "id", "ID!"
              t.field "name", "String"
              t.field "age", "Int"
              t.field "nationality", "String"
              t.index "people"
            end

            api.object_type "Company" do |t|
              t.implements "Organization"
              t.field "id", "ID!"
              t.field "name", "String"
              t.field "age", "Int"
              t.field "stock_ticker", "String"
              t.index "companies"
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

          expect(sort_order_type_from(result, "Inventor")).to eq(<<~EOS.strip)
            enum InventorSortOrderInput {
              id_ASC
              id_DESC
              name_ASC
              name_DESC
              age_ASC
              age_DESC
              nationality_ASC
              nationality_DESC
              stock_ticker_ASC
              stock_ticker_DESC
            }
          EOS
        end
      end
    end
  end
end
