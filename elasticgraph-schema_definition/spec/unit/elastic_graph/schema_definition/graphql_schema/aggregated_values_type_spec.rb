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
    RSpec.describe "GraphQL schema generation", "an `*AggregatedValues` type" do
      include_context "GraphQL schema spec support"

      with_both_casing_forms do
        it "includes a field for each aggregatable numeric field" do
          results = define_schema do |schema|
            schema.object_type "Widget" do |t|
              t.field "id", "ID", aggregatable: false
              t.field "cost", "Int!" do |f|
                f.documentation "The cost of the widget."
              end
              t.field "cost_float", "Float!"
              t.field "cost_json_safe_long", "JsonSafeLong"
              t.field "cost_long_string", "LongString"
              t.field "cost_byte", "Int!" do |f|
                f.mapping type: "byte"
              end
              t.field "cost_short", "Int" do |f|
                f.mapping type: "short"
              end
              t.field "size", "Int", aggregatable: false  # opting out of being aggregatable
              t.index "widgets"
            end
          end

          expect(aggregated_values_type_from(results, "Widget", include_docs: true)).to eq(<<~EOS.strip)
            """
            Type used to perform aggregation computations on `Widget` fields.
            """
            type WidgetAggregatedValues {
              """
              Computed aggregate values for the `cost` field:

              > The cost of the widget.
              """
              cost: IntAggregatedValues
              """
              Computed aggregate values for the `cost_float` field.
              """
              cost_float: FloatAggregatedValues
              """
              Computed aggregate values for the `cost_json_safe_long` field.
              """
              cost_json_safe_long: JsonSafeLongAggregatedValues
              """
              Computed aggregate values for the `cost_long_string` field.
              """
              cost_long_string: LongStringAggregatedValues
              """
              Computed aggregate values for the `cost_byte` field.
              """
              cost_byte: IntAggregatedValues
              """
              Computed aggregate values for the `cost_short` field.
              """
              cost_short: IntAggregatedValues
            }
          EOS
        end

        it "includes a field for each aggregatable date field (of any sort)" do
          results = define_schema do |schema|
            schema.object_type "Widget" do |t|
              t.field "id", "ID", aggregatable: false
              t.field "date", "Date"
              t.field "date_time", "DateTime"
              t.field "local_time", "LocalTime"
              t.index "widgets"
            end
          end

          expect(aggregated_values_type_from(results, "Widget")).to eq(<<~EOS.strip)
            type WidgetAggregatedValues {
              date: DateAggregatedValues
              date_time: DateTimeAggregatedValues
              local_time: LocalTimeAggregatedValues
            }
          EOS
        end

        it "does not care if the numeric fields are lists or scalars or nullable or not" do
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
              t.index "widgets"
            end
          end

          expect(aggregated_values_type_from(results, "Widget")).to eq(<<~EOS.strip)
            type WidgetAggregatedValues {
              id: NonNumericAggregatedValues
              some_string: NonNumericAggregatedValues
              some_string2: NonNumericAggregatedValues
              some_int: IntAggregatedValues
              some_int2: IntAggregatedValues
              some_float: FloatAggregatedValues
              some_float2: FloatAggregatedValues
              some_long: JsonSafeLongAggregatedValues
              some_long2: JsonSafeLongAggregatedValues
            }
          EOS
        end

        it "does not generate the type if no fields are aggregatable" do
          results = define_schema do |schema|
            schema.object_type "Widget" do |t|
              t.field "id", "ID", aggregatable: false
              t.field "size", "Int", aggregatable: false
              t.index "widgets"
            end
          end

          expect(aggregated_values_type_from(results, "Widget")).to eq nil
        end

        it "does not generate a field that references an `AggregatedValues` type when there are no aggregatable fields on it" do
          results = define_schema do |schema|
            schema.object_type "WidgetOptions" do |t|
              t.field "size", "Int", aggregatable: false
            end

            schema.object_type "Widget" do |t|
              t.field "id", "ID"
              t.field "options", "WidgetOptions"
              t.index "widgets"
            end
          end

          expect(aggregated_values_type_from(results, "WidgetOptions")).to eq nil
          expect(aggregated_values_type_from(results, "Widget")).to eq(<<~EOS.strip)
            type WidgetAggregatedValues {
              id: NonNumericAggregatedValues
            }
          EOS
        end

        it "generates the `AggregatedValues` based on the element type of a `paginated_collection_field` rather than the connection type" do
          results = define_schema do |schema|
            schema.object_type "WidgetOptions" do |t|
              t.field "size", "Int"
            end

            schema.object_type "Widget" do |t|
              t.field "id", "ID"
              t.paginated_collection_field "options", "WidgetOptions" do |f|
                f.mapping type: "object"
              end
              t.index "widgets"
            end
          end

          expect(aggregated_values_type_from(results, "Widget")).to eq(<<~EOS.strip)
            type WidgetAggregatedValues {
              id: NonNumericAggregatedValues
              options: WidgetOptionsAggregatedValues
            }
          EOS
        end

        it "hides `nested` fields on the `AggregatedValues` type since we don't yet support them" do
          results = define_schema do |schema|
            schema.object_type "WidgetOptions" do |t|
              t.field "size", "Int"
            end

            schema.object_type "Widget" do |t|
              t.field "id", "ID"
              t.paginated_collection_field "options", "WidgetOptions" do |f|
                f.mapping type: "nested"
              end
              t.index "widgets"
            end
          end

          expect(aggregated_values_type_from(results, "Widget")).to eq(<<~EOS.strip)
            type WidgetAggregatedValues {
              id: NonNumericAggregatedValues
            }
          EOS
        end

        it "avoids making `mapping type: 'text'` fields aggregatable since Elasticsearch and OpenSearch don't support it" do
          results = define_schema do |schema|
            schema.object_type "Widget" do |t|
              t.field "id", "ID"
              t.field "name", "String"
              t.field "description", "String" do |f|
                f.mapping type: "text"
              end
              t.index "widgets"
            end
          end

          expect(aggregated_values_type_from(results, "Widget")).to eq(<<~EOS.strip)
            type WidgetAggregatedValues {
              id: NonNumericAggregatedValues
              name: NonNumericAggregatedValues
            }
          EOS
        end

        it "references a nested `*AggregatedValues` type for embedded object fields" do
          results = define_schema do |schema|
            schema.object_type "Widget" do |t|
              t.field "id", "ID"
              t.field "cost", "Int"
              t.field "widget_options", "WidgetOptions"
              t.index "widgets"
            end

            schema.object_type "WidgetOptions" do |t|
              t.field "size", "Int"
            end
          end

          expect(aggregated_values_type_from(results, "Widget")).to eq(<<~EOS.strip)
            type WidgetAggregatedValues {
              id: NonNumericAggregatedValues
              cost: IntAggregatedValues
              widget_options: WidgetOptionsAggregatedValues
            }
          EOS

          expect(aggregated_values_type_from(results, "WidgetOptions")).to eq(<<~EOS.strip)
            type WidgetOptionsAggregatedValues {
              size: IntAggregatedValues
            }
          EOS
        end

        it "uses `NonNumericAggregatedValues` for object fields with custom mapping types" do
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

          expect(aggregated_values_type_from(results, "Widget")).to eq(<<~EOS.strip)
            type WidgetAggregatedValues {
              id: NonNumericAggregatedValues
              point1: NonNumericAggregatedValues
              point2: Point2AggregatedValues
            }
          EOS

          expect(aggregated_values_type_from(results, "Point1")).to eq(nil)

          expect(aggregated_values_type_from(results, "Point2")).to eq(<<~EOS.strip)
            type Point2AggregatedValues {
              x: FloatAggregatedValues
              y: FloatAggregatedValues
            }
          EOS
        end

        it "makes object fields with custom mapping options aggregatable so long as the `type` hasn't been customized" do
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

          expect(aggregated_values_type_from(results, "Widget")).to eq(<<~EOS.strip)
            type WidgetAggregatedValues {
              id: NonNumericAggregatedValues
              point: PointAggregatedValues
            }
          EOS

          expect(aggregated_values_type_from(results, "Point")).to eq(<<~EOS.strip)
            type PointAggregatedValues {
              x: FloatAggregatedValues
              y: FloatAggregatedValues
            }
          EOS
        end

        it "does not make relation fields aggregatable (but still makes a non-relation field of the same type aggregatable)" do
          results = define_schema do |schema|
            schema.object_type "Component" do |t|
              t.field "id", "ID"
              t.field "cost", "Int"

              t.index "components"
            end

            schema.object_type "Widget" do |t|
              t.field "id", "ID"
              t.relates_to_one "related_component", "Component", via: "component_id", dir: :out
              t.field "embedded_component", "Component"

              t.index "widgets"
            end
          end

          expect(aggregated_values_type_from(results, "Widget")).to eq(<<~EOS.strip)
            type WidgetAggregatedValues {
              id: NonNumericAggregatedValues
              embedded_component: ComponentAggregatedValues
            }
          EOS
        end

        it "allows the aggregated values fields to be customized" do
          result = define_schema do |api|
            api.raw_sdl "directive @external on FIELD_DEFINITION"

            api.object_type "WidgetOptions" do |t|
              t.field "size", "Int"
            end

            api.object_type "Widget" do |t|
              t.field "cost", "Int" do |f|
                f.customize_aggregated_values_field do |avf|
                  avf.directive "deprecated"
                end

                f.customize_aggregated_values_field do |avf|
                  avf.directive "external"
                end
              end

              t.field "options", "WidgetOptions" do |f|
                f.customize_aggregated_values_field do |avf|
                  avf.directive "deprecated"
                end
              end

              t.field "size", "Int" do |f|
                f.customize_aggregated_values_field do |avf|
                  avf.directive "external"
                end
              end
            end
          end

          expect(aggregated_values_type_from(result, "Widget")).to eq(<<~EOS.strip)
            type WidgetAggregatedValues {
              cost: IntAggregatedValues @deprecated @external
              options: WidgetOptionsAggregatedValues @deprecated
              size: IntAggregatedValues @external
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

            expect(aggregated_values_type_from(results, "Widget")).to eq(<<~EOS.strip)
              type WidgetAggregatedValues {
                id: NonNumericAggregatedValues
                inventor: InventorAggregatedValues
              }
            EOS
          end

          it "defines the type using the set union of the fields of the subtypes" do
            result = define_schema do |api|
              api.object_type "Person" do |t|
                link_subtype_to_supertype(t, "Inventor")
                t.field "age", "Int"
                t.field "income", "Float"
              end

              api.object_type "Company" do |t|
                link_subtype_to_supertype(t, "Inventor")
                t.field "age", "Int"
                t.field "share_value", "Float"
              end

              api.public_send type_def_method, "Inventor" do |t|
                link_supertype_to_subtypes(t, "Person", "Company")
              end
            end

            expect(aggregated_values_type_from(result, "Inventor")).to eq(<<~EOS.strip)
              type InventorAggregatedValues {
                age: IntAggregatedValues
                income: FloatAggregatedValues
                share_value: FloatAggregatedValues
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

            expect(aggregated_values_type_from(result, "Inventor")).to eq(<<~EOS.strip)
              type InventorAggregatedValues {
                age: IntAggregatedValues
                income: FloatAggregatedValues
                share_value: FloatAggregatedValues
              }
            EOS
          end
        end
      end
    end
  end
end
