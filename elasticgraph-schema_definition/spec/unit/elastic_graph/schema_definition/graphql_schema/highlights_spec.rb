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
    RSpec.describe "GraphQL schema generation", "highlights" do
      include_context "GraphQL schema spec support"

      with_both_casing_forms do
        it "defines a `Highlights` type for each indexed type" do
          result = define_schema do |api|
            api.object_type "Widget" do |t|
              t.field "id", "ID!" do |f|
                f.documentation <<~EOD
                  The identifier.

                  Another paragraph.
                EOD
              end

              t.field "string", "String"

              t.index "widgets"
            end
          end

          expect(highlights_type_from(result, "Widget", include_docs: true)).to eq(<<~EOS.strip)
            """
            Type used to request desired `Widget` search highlight fields.
            """
            type WidgetHighlights {
              """
              Search highlights for the `id`, providing snippets of the matching text:

              > The identifier.
              >
              > Another paragraph.
              """
              id: [String!]!
              """
              Search highlights for the `string`, providing snippets of the matching text.
              """
              string: [String!]!
            }
          EOS
        end

        it "only defines highlight fields with a keyword or text mapping" do
          result = define_schema do |api|
            api.enum_type "Size" do |t|
              t.values "SMALL", "MEDIUM", "LARGE"
            end

            api.scalar_type "CustomNumber" do |t|
              t.json_schema type: "number"
              t.mapping type: "integer"
            end

            api.scalar_type "CustomKeyword" do |t|
              t.json_schema type: "string"
              t.mapping type: "keyword"
            end

            api.object_type "Widget" do |t|
              t.field "id", "ID!" # ID uses keyword
              t.field "string", "String"

              t.field "text", "String" do |f|
                f.mapping type: "text"
              end

              t.field "match_only_text", "String" do |f|
                f.mapping type: "match_only_text"
              end

              t.field "size", "Size" # Enum types use keyword, too
              t.field "custom_keyword", "CustomKeyword"

              # None of these use the keyword mapping type and should be omitted from the highlights type below.
              t.field "int", "Int"
              t.field "float", "Float"
              t.field "boolean", "Boolean"
              t.field "date", "Date"
              t.field "date_time", "DateTime"
              t.field "local_time", "LocalTime"
              t.field "json_safe_long", "JsonSafeLong"
              t.field "long_string", "LongString"
              t.field "custom_number", "CustomNumber"

              t.index "widgets"
            end
          end

          expect(highlights_type_from(result, "Widget")).to eq(<<~EOS.strip)
            type WidgetHighlights {
              id: [String!]!
              string: [String!]!
              text: [String!]!
              match_only_text: [String!]!
              size: [String!]!
              custom_keyword: [String!]!
            }
          EOS
        end

        it "defines scalar highlight fields as `[String!]!` regardless of what non-null or list wrappings the source fields have" do
          result = define_schema do |api|
            api.object_type "Widget" do |t|
              t.field "id", "ID"
              t.field "id", "ID"
              t.field "id_non_null", "ID!"
              t.field "id_list", "[ID]"
              t.field "id_non_null_list", "[ID!]!"

              t.index "widgets"
            end
          end

          expect(highlights_type_from(result, "Widget")).to eq(<<~EOS.strip)
            type WidgetHighlights {
              id: [String!]!
              id_non_null: [String!]!
              id_list: [String!]!
              id_non_null_list: [String!]!
            }
          EOS
        end

        it "defines multiple levels of `Highlights` types to match a multi-level source schema" do
          result = define_schema do |api|
            api.object_type "WidgetOptions" do |t|
              t.field "color", "String"
              t.field "sub_options", "WidgetSubOptions"
              t.field "sub_options_nested", "[WidgetSubOptions!]!" do |f|
                f.mapping type: "nested"
              end

              t.field "sub_options_object", "[WidgetSubOptions!]!" do |f|
                f.mapping type: "object"
              end
            end

            api.object_type "WidgetSubOptions" do |t|
              t.field "sub_color", "String"
            end

            api.object_type "Widget" do |t|
              t.field "id", "ID"
              t.field "options", "WidgetOptions"
              t.field "options_nested", "[WidgetOptions!]!" do |f|
                f.mapping type: "nested"
              end

              t.field "options_object", "[WidgetOptions!]!" do |f|
                f.mapping type: "object"
              end

              t.index "widgets"
            end
          end

          expect(highlights_type_from(result, "Widget")).to eq(<<~EOS.strip)
            type WidgetHighlights {
              id: [String!]!
              options: WidgetOptionsHighlights
              options_nested: WidgetOptionsHighlights
              options_object: WidgetOptionsHighlights
            }
          EOS

          expect(highlights_type_from(result, "WidgetOptions")).to eq(<<~EOS.strip)
            type WidgetOptionsHighlights {
              color: [String!]!
              sub_options: WidgetSubOptionsHighlights
              sub_options_nested: WidgetSubOptionsHighlights
              sub_options_object: WidgetSubOptionsHighlights
            }
          EOS

          expect(highlights_type_from(result, "WidgetSubOptions")).to eq(<<~EOS.strip)
            type WidgetSubOptionsHighlights {
              sub_color: [String!]!
            }
          EOS
        end

        it "does not define highlights for an indexing only field" do
          result = define_schema do |api|
            api.object_type "Widget" do |t|
              t.field "id", "ID!", indexing_only: true
              t.field "string", "String", indexing_only: true
              t.field "tag", "String"

              t.index "widgets"
            end
          end

          expect(highlights_type_from(result, "Widget")).to eq(<<~EOS.strip)
            type WidgetHighlights {
              tag: [String!]!
            }
          EOS
        end

        it "does not define a `Highlights` type if there are no highlightable fields" do
          result = define_schema do |api|
            api.object_type "WidgetOptions" do |t|
              t.field "size", "Int"
              t.field "sub_options", "WidgetSubOptions"
            end

            api.object_type "WidgetSubOptions" do |t|
              t.field "sub_size", "Int"
            end

            api.object_type "Widget" do |t|
              t.field "id", "ID", indexing_only: true
              t.field "options", "WidgetOptions"
              t.field "count", "Int"

              t.index "widgets"
            end
          end

          expect(highlights_type_from(result, "Widget")).to be nil
          expect(highlights_type_from(result, "WidgetOptions")).to be nil
          expect(highlights_type_from(result, "WidgetSubOptions")).to be nil
        end

        it "supports `highlightable`" do
          result = define_schema do |api|
            api.object_type "WidgetOptions" do |t|
              t.field "color1", "String", highlightable: true
              t.field "color2", "String", highlightable: false
              t.field "size1", "Int", highlightable: true
              t.field "size2", "Int", highlightable: false
            end

            api.object_type "Widget" do |t|
              t.field "id", "ID", highlightable: false
              t.field "name1", "ID", highlightable: true
              t.field "name2", "ID", highlightable: false
              t.field "count1", "Int", highlightable: true
              t.field "count2", "Int", highlightable: false
              t.field "options1", "WidgetOptions", highlightable: true
              t.field "options2", "WidgetOptions", highlightable: false

              t.index "widgets"
            end
          end

          expect(highlights_type_from(result, "Widget")).to eq(<<~EOS.strip)
            type WidgetHighlights {
              name1: [String!]!
              count1: [String!]!
              options1: WidgetOptionsHighlights
            }
          EOS

          expect(highlights_type_from(result, "WidgetOptions")).to eq(<<~EOS.strip)
            type WidgetOptionsHighlights {
              color1: [String!]!
              size1: [String!]!
            }
          EOS
        end

        it "avoids defining highlights for a relationship field" do
          result = define_schema do |api|
            api.object_type "Component" do |t|
              t.field "id", "ID"
              t.relates_to_one "widget", "Widget", via: "widget_id", dir: :out
              t.index "components"
            end

            api.object_type "Widget" do |t|
              t.field "id", "ID"
              t.relates_to_one "components", "Component", via: "widget_id", dir: :in
              t.index "widgets"
            end
          end

          expect(highlights_type_from(result, "Widget")).to eq(<<~EOS.strip)
            type WidgetHighlights {
              id: [String!]!
            }
          EOS

          expect(highlights_type_from(result, "Component")).to eq(<<~EOS.strip)
            type ComponentHighlights {
              id: [String!]!
            }
          EOS
        end

        it "supports highlights on paginated collection fields" do
          result = define_schema do |api|
            api.object_type "WidgetOptions" do |t|
              t.field "color", "String"
            end

            api.object_type "Widget" do |t|
              t.field "id", "ID"
              t.paginated_collection_field "tags", "String"
              t.paginated_collection_field "options", "WidgetOptions" do |f|
                f.mapping type: "object"
              end

              t.index "widgets"
            end
          end

          expect(highlights_type_from(result, "Widget")).to eq(<<~EOS.strip)
            type WidgetHighlights {
              id: [String!]!
              tags: [String!]!
              options: WidgetOptionsHighlights
            }
          EOS

          expect(highlights_type_from(result, "WidgetOptions")).to eq(<<~EOS.strip)
            type WidgetOptionsHighlights {
              color: [String!]!
            }
          EOS
        end

        it "avoids defining highlights for object types that have use a custom mapping type" do
          result = define_schema do |api|
            api.object_type "Point" do |t|
              t.field "x", "String"
              t.field "y", "String"
              t.mapping meta: {defined_by: "ElasticGraph"} # mapping customizations that aren't on the `type` should be fine
            end

            api.object_type "PointWithCustomMappingType" do |t|
              t.field "x", "String"
              t.field "y", "String"
              t.mapping type: "point"
            end

            api.object_type "Widget" do |t|
              t.field "id", "ID!", highlightable: false
              t.field "point", "Point"
              t.field "point_with_custom_mapping_type", "PointWithCustomMappingType"
              t.index "widgets"
            end
          end

          expect(highlights_type_from(result, "Widget")).to eq(<<~EOS.strip)
            type WidgetHighlights {
              point: PointHighlights
            }
          EOS

          expect(highlights_type_from(result, "Point")).to eq(<<~EOS.strip)
            type PointHighlights {
              x: [String!]!
              y: [String!]!
            }
          EOS

          expect(highlights_type_from(result, "PointWithCustomMappingType")).to be nil
        end

        it "does not automatically copy directives to the derived field" do
          result = define_schema do |api|
            api.object_type "Widget" do |t|
              t.field "name", "String" do |f|
                f.directive "deprecated", reason: "Use `new_name` instead."
              end
            end
          end

          expect(highlights_type_from(result, "Widget")).to eq(<<~EOS.strip)
            type WidgetHighlights {
              name: [String!]!
            }
          EOS
        end

        it "allows highlights fields to be customized using a block" do
          result = define_schema do |api|
            api.raw_sdl "directive @external on FIELD_DEFINITION"

            api.object_type "WidgetOptions" do |t|
              t.field "color", "String"
            end

            api.object_type "Widget" do |t|
              t.field "name", "String" do |f|
                f.customize_highlights_field do |gbf|
                  gbf.directive "deprecated"
                end

                f.customize_highlights_field do |gbf|
                  gbf.directive "external"
                end
              end

              t.field "options", "WidgetOptions" do |f|
                f.customize_highlights_field do |gbf|
                  gbf.directive "deprecated"
                end
              end
            end
          end

          expect(highlights_type_from(result, "Widget")).to eq(<<~EOS.strip)
            type WidgetHighlights {
              name: [String!]! @deprecated @external
              options: WidgetOptionsHighlights @deprecated
            }
          EOS
        end

        it "respects a configured type name override when generating the highlights field from a `paginated_collection_field`" do
          result = define_schema(type_name_overrides: {Point: "Point2"}) do |api|
            api.object_type "Point" do |t|
              t.field "x", "String"
              t.field "y", "String"
            end

            api.object_type "Widget" do |t|
              t.field "id", "ID"
              t.paginated_collection_field "points", "Point" do |f|
                f.mapping type: "object"
              end

              t.index "widgets"
            end
          end

          expect(highlights_type_from(result, "Widget")).to eq(<<~EOS.strip)
            type WidgetHighlights {
              id: [String!]!
              points: Point2Highlights
            }
          EOS
        end

        shared_examples_for "a type with subtypes" do |type_def_method|
          it "defines a field for an abstract type if that abstract type has highlightable fields" do
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

            expect(highlights_type_from(results, "Widget")).to eq(<<~EOS.strip)
              type WidgetHighlights {
                id: [String!]!
                inventor: InventorHighlights
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

            expect(highlights_type_from(result, "Inventor")).to eq(<<~EOS.strip)
              type InventorHighlights {
                name: [String!]!
                nationality: [String!]!
                stock_ticker: [String!]!
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
                t.field "name", "String"
                t.field "income", "String"
              end

              api.object_type "Company" do |t|
                t.implements "Organization"
                t.field "name", "String"
                t.field "share_value", "String"
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

            expect(highlights_type_from(result, "Inventor")).to eq(<<~EOS.strip)
              type InventorHighlights {
                name: [String!]!
                income: [String!]!
                share_value: [String!]!
              }
            EOS
          end
        end
      end
    end
  end
end
