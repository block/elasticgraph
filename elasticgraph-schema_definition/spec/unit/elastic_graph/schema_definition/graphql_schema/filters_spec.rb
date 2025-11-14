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
    RSpec.describe "GraphQL schema generation", "filters" do
      include_context "GraphQL schema spec support"

      with_both_casing_forms do
        it "defines filter types for indexed types with docs" do
          result = define_schema do |api|
            api.object_type "WidgetOptions" do |t|
              t.field "size", "Int"
            end

            api.object_type "Widget" do |t|
              t.field "id", "ID!" do |f|
                f.documentation <<~EOD
                  The identifier.

                  Another paragraph.
                EOD
              end

              t.field "the_options", "WidgetOptions"
              t.field "cost", "Int"

              t.index "widgets"
            end
          end

          expect(filter_type_from(result, "Widget", include_docs: true)).to eq(<<~EOS.strip)
            """
            Input type used to specify filters on `Widget` fields.

            Will match all documents if passed as an empty object (or as `null`).
            """
            input WidgetFilterInput {
              """
              Matches records where any of the provided sub-filters evaluate to true.
              This works just like an OR operator in SQL.

              When `null` is passed, matches all documents.
              When an empty list is passed, this part of the filter matches no documents.
              """
              #{schema_elements.any_of}: [WidgetFilterInput!]
              """
              Matches records where all of the provided sub-filters evaluate to true. This works just like an AND operator in SQL.

              Note: multiple filters are automatically ANDed together. This is only needed when you have multiple filters that can't
              be provided on a single `WidgetFilterInput` input because of collisions between key names. For example, if you want to AND multiple
              OR'd sub-filters (the equivalent of (A OR B) AND (C OR D)), you could do #{schema_elements.all_of}: [{#{schema_elements.any_of}: [...]}, {#{schema_elements.any_of}: [...]}].

              When `null` or an empty list is passed, matches all documents.
              """
              #{schema_elements.all_of}: [WidgetFilterInput!]
              """
              Matches records where the provided sub-filter evaluates to false.
              This works just like a NOT operator in SQL.

              When `null` or an empty object is passed, matches no documents.
              """
              #{schema_elements.not}: WidgetFilterInput
              """
              Used to filter on the `id` field:

              > The identifier.
              >
              > Another paragraph.

              When `null` or an empty object is passed, matches all documents.
              """
              id: IDFilterInput
              """
              Used to filter on the `the_options` field.

              When `null` or an empty object is passed, matches all documents.
              """
              the_options: WidgetOptionsFilterInput
              """
              Used to filter on the `cost` field.

              When `null` or an empty object is passed, matches all documents.
              """
              cost: IntFilterInput
            }
          EOS
        end

        it "defines filter types for embedded types" do
          result = define_schema do |api|
            api.object_type "WidgetOptions" do |t|
              t.field "size", "Int!" do |f|
                f.documentation "The size of the widget."
              end

              t.field "main_color", "String"
            end
          end

          expect(filter_type_from(result, "WidgetOptions", include_docs: true)).to eq(<<~EOS.strip)
            """
            Input type used to specify filters on `WidgetOptions` fields.

            Will match all documents if passed as an empty object (or as `null`).
            """
            input WidgetOptionsFilterInput {
              """
              Matches records where any of the provided sub-filters evaluate to true.
              This works just like an OR operator in SQL.

              When `null` is passed, matches all documents.
              When an empty list is passed, this part of the filter matches no documents.
              """
              #{schema_elements.any_of}: [WidgetOptionsFilterInput!]
              """
              Matches records where all of the provided sub-filters evaluate to true. This works just like an AND operator in SQL.

              Note: multiple filters are automatically ANDed together. This is only needed when you have multiple filters that can't
              be provided on a single `WidgetOptionsFilterInput` input because of collisions between key names. For example, if you want to AND multiple
              OR'd sub-filters (the equivalent of (A OR B) AND (C OR D)), you could do #{schema_elements.all_of}: [{#{schema_elements.any_of}: [...]}, {#{schema_elements.any_of}: [...]}].

              When `null` or an empty list is passed, matches all documents.
              """
              #{schema_elements.all_of}: [WidgetOptionsFilterInput!]
              """
              Matches records where the provided sub-filter evaluates to false.
              This works just like a NOT operator in SQL.

              When `null` or an empty object is passed, matches no documents.
              """
              #{schema_elements.not}: WidgetOptionsFilterInput
              """
              Used to filter on the `size` field:

              > The size of the widget.

              When `null` or an empty object is passed, matches all documents.
              """
              size: IntFilterInput
              """
              Used to filter on the `main_color` field.

              When `null` or an empty object is passed, matches all documents.
              """
              main_color: StringFilterInput
            }
          EOS

          expect(list_filter_type_from(result, "WidgetOptions", include_docs: true)).to eq(<<~EOS.strip)
            """
            Input type used to specify filters on `[WidgetOptions]` fields.

            Will match all documents if passed as an empty object (or as `null`).
            """
            input WidgetOptionsListFilterInput {
              """
              Matches records where any of the provided sub-filters evaluate to true.
              This works just like an OR operator in SQL.

              When `null` is passed, matches all documents.
              When an empty list is passed, this part of the filter matches no documents.
              """
              #{schema_elements.any_of}: [WidgetOptionsListFilterInput!]
              """
              Matches records where all of the provided sub-filters evaluate to true. This works just like an AND operator in SQL.

              Note: multiple filters are automatically ANDed together. This is only needed when you have multiple filters that can't
              be provided on a single `WidgetOptionsListFilterInput` input because of collisions between key names. For example, if you want to AND multiple
              OR'd sub-filters (the equivalent of (A OR B) AND (C OR D)), you could do #{schema_elements.all_of}: [{#{schema_elements.any_of}: [...]}, {#{schema_elements.any_of}: [...]}].

              When `null` or an empty list is passed, matches all documents.
              """
              #{schema_elements.all_of}: [WidgetOptionsListFilterInput!]
              """
              Matches records where the provided sub-filter evaluates to false.
              This works just like a NOT operator in SQL.

              When `null` or an empty object is passed, matches no documents.
              """
              #{schema_elements.not}: WidgetOptionsListFilterInput
              """
              Matches records where any of the list elements match the provided sub-filter.

              When `null` or an empty object is passed, matches all documents.
              """
              #{schema_elements.any_satisfy}: WidgetOptionsFilterInput
              """
              Used to filter on the number of non-null elements in this list field.

              When `null` or an empty object is passed, matches all documents.
              """
              #{schema_elements.count}: IntFilterInput
            }
          EOS
        end

        it "does not define or reference a filter type for embedded object types that have no filterable fields" do
          result = define_schema do |api|
            api.object_type "WidgetOptions" do |t|
              t.field "size", "Int", filterable: false
            end

            api.object_type "Widget" do |t|
              t.field "id", "ID!"
              t.field "nullable_options", "WidgetOptions"
              t.field "non_nullable_options", "WidgetOptions!"
              t.index "widgets"
            end
          end

          expect(filter_type_from(result, "WidgetOptions")).to be nil
          expect(filter_type_from(result, "Widget")).to eq(<<~EOS.strip)
            input WidgetFilterInput {
              #{schema_elements.any_of}: [WidgetFilterInput!]
              #{schema_elements.all_of}: [WidgetFilterInput!]
              #{schema_elements.not}: WidgetFilterInput
              id: IDFilterInput
            }
          EOS
        end

        it "does not define or reference a filter type (or list filter type) for embedded object types that have a custom mapping type" do
          result = define_schema do |api|
            api.object_type "PointWithCustomMapping" do |t|
              t.field "x", "Float"
              t.field "y", "Float"
              t.mapping type: "point"
            end

            api.object_type "Point" do |t|
              t.field "x", "Float"
              t.field "y", "Float"
            end

            api.object_type "Widget" do |t|
              t.field "id", "ID!"
              t.field "nullable_point_with_custom_mapping", "PointWithCustomMapping"
              t.field "non_null_point_with_custom_mapping", "PointWithCustomMapping!"
              t.field "nullable_point", "Point"
              t.field "non_null_point", "Point!"
              t.index "widgets"
            end
          end

          expect(filter_type_from(result, "PointWithCustomMapping")).to be nil
          expect(list_filter_type_from(result, "PointWithCustomMapping")).to be nil
          expect(list_element_filter_type_from(result, "PointWithCustomMapping")).to be nil
          expect(filter_type_from(result, "Point")).not_to be nil
          expect(list_filter_type_from(result, "Point")).not_to be nil
          expect(list_element_filter_type_from(result, "Point")).to be nil
          expect(filter_type_from(result, "Widget")).to eq(<<~EOS.strip)
            input WidgetFilterInput {
              #{schema_elements.any_of}: [WidgetFilterInput!]
              #{schema_elements.all_of}: [WidgetFilterInput!]
              #{schema_elements.not}: WidgetFilterInput
              id: IDFilterInput
              nullable_point: PointFilterInput
              non_null_point: PointFilterInput
            }
          EOS
        end

        it "does not consider `type: object` to be a custom mapping type for an object (since that is the default)" do
          result = define_schema do |api|
            api.object_type "Point" do |t|
              t.field "x", "Float"
              t.field "y", "Float"
              t.mapping type: "object"
            end

            api.object_type "Widget" do |t|
              t.field "id", "ID!"
              t.field "nullable_point", "Point"
              t.field "non_null_point", "Point!"
              t.index "widgets"
            end
          end

          expect(filter_type_from(result, "Point")).not_to be nil
          expect(list_filter_type_from(result, "Point")).not_to be nil
          expect(list_element_filter_type_from(result, "Point")).to be nil
          expect(filter_type_from(result, "Widget")).to eq(<<~EOS.strip)
            input WidgetFilterInput {
              #{schema_elements.any_of}: [WidgetFilterInput!]
              #{schema_elements.all_of}: [WidgetFilterInput!]
              #{schema_elements.not}: WidgetFilterInput
              id: IDFilterInput
              nullable_point: PointFilterInput
              non_null_point: PointFilterInput
            }
          EOS
        end

        it "makes object fields with custom mapping options filterable so long as the `type` hasn't been customized" do
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

          expect(filter_type_from(result, "Point")).not_to be nil
          expect(list_filter_type_from(result, "Point")).not_to be nil
          expect(list_element_filter_type_from(result, "Point")).to be nil
          expect(filter_type_from(result, "Widget")).to eq(<<~EOS.strip)
            input WidgetFilterInput {
              #{schema_elements.any_of}: [WidgetFilterInput!]
              #{schema_elements.all_of}: [WidgetFilterInput!]
              #{schema_elements.not}: WidgetFilterInput
              id: IDFilterInput
              nullable_point: PointFilterInput
              non_null_point: PointFilterInput
            }
          EOS
        end

        it "does not define or reference a filter field for a relation field" do
          result = define_schema do |api|
            api.object_type "Component" do |t|
              t.field "id", "ID"
              t.relates_to_one "widget", "Widget", via: "widget_id", dir: :out
              t.index "components"
            end

            api.object_type "Widget" do |t|
              t.field "id", "ID!"
              t.relates_to_many "components", "Component", via: "widget_id", dir: :in, singular: "component"
              t.index "widgets"
            end
          end

          expect(filter_type_from(result, "Widget")).to eq(<<~EOS.strip)
            input WidgetFilterInput {
              #{schema_elements.any_of}: [WidgetFilterInput!]
              #{schema_elements.all_of}: [WidgetFilterInput!]
              #{schema_elements.not}: WidgetFilterInput
              id: IDFilterInput
            }
          EOS
        end

        it "does not recurse infinitely when dealing with self-referential relations" do
          result = define_schema do |api|
            api.object_type "Widget" do |t|
              t.field "id", "ID", filterable: false
              t.relates_to_one "parent_widget", "Widget", via: "parent_widget_id", dir: :in
              t.index "widgets"
            end
          end

          expect(filter_type_from(result, "Widget")).to be nil
        end

        it "does not copy custom directives from the source field to the filter field because we can't be sure the directive is valid on an input field" do
          result = define_schema do |api|
            api.raw_sdl "directive @foo(bar: Int) on FIELD_DEFINITION"
            api.raw_sdl "directive @bar on FIELD_DEFINITION"

            api.object_type "WidgetOptions" do |t|
              t.field "size", "Int!" do |f|
                f.directive "foo", bar: 1
              end

              t.field "main_color", "String" do |f|
                f.directive "bar"
              end
            end
          end

          # Directives are expected to define what elements they are valid on, e.g.:
          # directive @key(fields: _FieldSet!) repeatable on OBJECT | INTERFACE
          #
          # Input objects are different enum values for the `on`, and we can't count on
          # directives that are valid on object fields necessarily being valid on input
          # fields, so we do not copy them to the filter fields.
          #
          # If there's a need to copy them forward, we can revisit this, but we'll have to
          # interpret the directive definitions to know if it's safe to copy them forward,
          # or allow users to configure if they get copied onto the filter.
          expect(filter_type_from(result, "WidgetOptions")).to eq(<<~EOS.strip)
            input WidgetOptionsFilterInput {
              #{schema_elements.any_of}: [WidgetOptionsFilterInput!]
              #{schema_elements.all_of}: [WidgetOptionsFilterInput!]
              #{schema_elements.not}: WidgetOptionsFilterInput
              size: IntFilterInput
              main_color: StringFilterInput
            }
          EOS
        end

        it "defines filter types for enum types with docs" do
          result = define_schema do |api|
            api.enum_type "Color" do |e|
              e.values "RED", "GREEN", "BLUE"
            end
          end

          expect(filter_type_from(result, "Color", include_docs: true)).to eq(<<~EOS.strip)
            """
            Input type used to specify filters on `Color` fields.

            Will match all documents if passed as an empty object (or as `null`).
            """
            input ColorFilterInput {
              """
              Matches records where any of the provided sub-filters evaluate to true.
              This works just like an OR operator in SQL.

              When `null` is passed, matches all documents.
              When an empty list is passed, this part of the filter matches no documents.
              """
              #{schema_elements.any_of}: [ColorFilterInput!]
              """
              Matches records where all of the provided sub-filters evaluate to true. This works just like an AND operator in SQL.

              Note: multiple filters are automatically ANDed together. This is only needed when you have multiple filters that can't
              be provided on a single `ColorFilterInput` input because of collisions between key names. For example, if you want to AND multiple
              OR'd sub-filters (the equivalent of (A OR B) AND (C OR D)), you could do #{schema_elements.all_of}: [{#{schema_elements.any_of}: [...]}, {#{schema_elements.any_of}: [...]}].

              When `null` or an empty list is passed, matches all documents.
              """
              #{schema_elements.all_of}: [ColorFilterInput!]
              """
              Matches records where the provided sub-filter evaluates to false.
              This works just like a NOT operator in SQL.

              When `null` or an empty object is passed, matches no documents.
              """
              #{schema_elements.not}: ColorFilterInput
              """
              Matches records where the field value is equal to any of the provided values.
              This works just like an IN operator in SQL.

              When `null` is passed, matches all documents. When an empty list is passed,
              this part of the filter matches no documents. When `null` is passed in the
              list, this part of the filter matches records where the field value is `null`.
              """
              #{schema_elements.equal_to_any_of}: [ColorInput]
            }
          EOS

          expect(list_element_filter_type_from(result, "Color", include_docs: true)).to eq(<<~EOS.strip)
            """
            Input type used to specify filters on elements of a `[Color]` field.

            Will match all documents if passed as an empty object (or as `null`).
            """
            input ColorListElementFilterInput {
              """
              Matches records where any of the provided sub-filters evaluate to true.
              This works just like an OR operator in SQL.

              When `null` is passed, matches all documents.
              When an empty list is passed, this part of the filter matches no documents.
              """
              #{schema_elements.any_of}: [ColorListElementFilterInput!]
              """
              Matches records where all of the provided sub-filters evaluate to true. This works just like an AND operator in SQL.

              Note: multiple filters are automatically ANDed together. This is only needed when you have multiple filters that can't
              be provided on a single `ColorListElementFilterInput` input because of collisions between key names. For example, if you want to AND multiple
              OR'd sub-filters (the equivalent of (A OR B) AND (C OR D)), you could do #{schema_elements.all_of}: [{#{schema_elements.any_of}: [...]}, {#{schema_elements.any_of}: [...]}].

              When `null` or an empty list is passed, matches all documents.
              """
              #{schema_elements.all_of}: [ColorListElementFilterInput!]
              """
              Matches records where the field value is equal to any of the provided values.
              This works just like an IN operator in SQL.

              When `null` is passed, matches all documents. When an empty list is passed,
              this part of the filter matches no documents. When `null` is passed in the
              list, this part of the filter matches records where the field value is `null`.
              """
              #{schema_elements.equal_to_any_of}: [ColorInput!]
            }
          EOS

          expect(list_filter_type_from(result, "Color", include_docs: true)).to eq(<<~EOS.strip)
            """
            Input type used to specify filters on `[Color]` fields.

            Will match all documents if passed as an empty object (or as `null`).
            """
            input ColorListFilterInput {
              """
              Matches records where any of the provided sub-filters evaluate to true.
              This works just like an OR operator in SQL.

              When `null` is passed, matches all documents.
              When an empty list is passed, this part of the filter matches no documents.
              """
              #{schema_elements.any_of}: [ColorListFilterInput!]
              """
              Matches records where all of the provided sub-filters evaluate to true. This works just like an AND operator in SQL.

              Note: multiple filters are automatically ANDed together. This is only needed when you have multiple filters that can't
              be provided on a single `ColorListFilterInput` input because of collisions between key names. For example, if you want to AND multiple
              OR'd sub-filters (the equivalent of (A OR B) AND (C OR D)), you could do #{schema_elements.all_of}: [{#{schema_elements.any_of}: [...]}, {#{schema_elements.any_of}: [...]}].

              When `null` or an empty list is passed, matches all documents.
              """
              #{schema_elements.all_of}: [ColorListFilterInput!]
              """
              Matches records where the provided sub-filter evaluates to false.
              This works just like a NOT operator in SQL.

              When `null` or an empty object is passed, matches no documents.
              """
              #{schema_elements.not}: ColorListFilterInput
              """
              Matches records where any of the list elements match the provided sub-filter.

              When `null` or an empty object is passed, matches all documents.
              """
              #{schema_elements.any_satisfy}: ColorListElementFilterInput
              """
              Used to filter on the number of non-null elements in this list field.

              When `null` or an empty object is passed, matches all documents.
              """
              #{schema_elements.count}: IntFilterInput
            }
          EOS
        end

        it "skips defining filters for `relates_to_one` fields" do
          result = define_schema do |api|
            api.object_type "Widget" do |t|
              t.field "id", "ID!"
              t.field "cost", "Int"
              t.relates_to_one "inventor", "Person", via: "inventor_id", dir: :out
              t.index "widgets"
            end

            api.object_type "Person" do |t|
              t.field "id", "ID"
              t.index "people"
            end
          end

          expect(filter_type_from(result, "Widget")).to eq(<<~EOS.strip)
            input WidgetFilterInput {
              #{schema_elements.any_of}: [WidgetFilterInput!]
              #{schema_elements.all_of}: [WidgetFilterInput!]
              #{schema_elements.not}: WidgetFilterInput
              id: IDFilterInput
              cost: IntFilterInput
            }
          EOS
        end

        it "allows the user to opt-out a field from being filterable" do
          result = define_schema do |api|
            api.object_type "WidgetOptions" do |t|
              t.field "size", "Int!"
              t.field "main_color", "String", filterable: false
            end
          end

          expect(filter_type_from(result, "WidgetOptions")).to eq(<<~EOS.strip)
            input WidgetOptionsFilterInput {
              #{schema_elements.any_of}: [WidgetOptionsFilterInput!]
              #{schema_elements.all_of}: [WidgetOptionsFilterInput!]
              #{schema_elements.not}: WidgetOptionsFilterInput
              size: IntFilterInput
            }
          EOS
        end

        it "provides a filter field for `GeoLocation` fields in spite of their using a custom mapping since we have support for the `GeoLocationFilterInput`" do
          result = define_schema do |api|
            api.object_type "Widget" do |t|
              t.field "id", "ID!"
              t.field "location", "GeoLocation"
              t.index "widgets"
            end
          end

          expect(filter_type_from(result, "Widget")).to eq(<<~EOS.strip)
            input WidgetFilterInput {
              #{schema_elements.any_of}: [WidgetFilterInput!]
              #{schema_elements.all_of}: [WidgetFilterInput!]
              not: WidgetFilterInput
              id: IDFilterInput
              location: GeoLocationFilterInput
            }
          EOS
        end

        it "uses `TextFilterInput` instead of `StringFilterInput` for text fields (even though they are strings in GraphQL)" do
          result = define_schema do |api|
            api.object_type "Widget" do |t|
              t.field "name", "String"
              t.field "description", "String" do |f|
                f.mapping type: "text"
              end

              t.field "description_alt", "String", name_in_index: "description", graphql_only: true
            end
          end

          expect(filter_type_from(result, "Widget")).to eq(<<~EOS.strip)
            input WidgetFilterInput {
              #{schema_elements.any_of}: [WidgetFilterInput!]
              #{schema_elements.all_of}: [WidgetFilterInput!]
              #{schema_elements.not}: WidgetFilterInput
              name: StringFilterInput
              description: TextFilterInput
              description_alt: TextFilterInput
            }
          EOS
        end

        it "avoids generating the filter type for an indexed type that has no filterable fields" do
          result = define_schema do |api|
            api.object_type "Widget" do |t|
              t.field "id", "ID!", filterable: false
              t.index "widgets"
            end
          end

          expect(filter_type_from(result, "Widget")).to eq nil
        end

        it "avoids generating the filter type for an embedded type that has no filterable fields" do
          result = define_schema do |api|
            api.object_type "Widget" do |t|
              t.field "id", "ID!", filterable: false
            end
          end

          expect(filter_type_from(result, "Widget")).to eq nil
        end

        it "allows filtering fields to be customized using a block" do
          result = define_schema do |api|
            api.object_type "Widget" do |t|
              t.field "id", "ID!" do |f|
                f.documentation "id field"

                f.customize_filter_field do |ff|
                  ff.directive "deprecated"
                end

                f.customize_filter_field do |ff|
                  ff.documentation "Custom filter field documentation!"
                end
              end
            end
          end

          # Demonstrate that the filtering customizations don't impact the `Widget.id` field.
          expect(type_def_from(result, "Widget", include_docs: true)).to eq(<<~EOS.strip)
            type Widget {
              """
              id field
              """
              id: ID!
            }
          EOS

          expect(filter_type_from(result, "Widget", include_docs: true)).to include(<<~EOS.strip)
              """
              Custom filter field documentation!
              """
              id: IDFilterInput @deprecated
            }
          EOS
        end

        it "avoids copying the `resolver` into the filter field" do
          results = []

          define_schema do |api|
            api.object_type "Widget" do |t|
              t.field "id", "ID!" do |f|
                f.resolve_with :list_records

                f.customize_filter_field do |ff|
                  results << ff.resolver
                end
              end
            end
          end

          expect(results.uniq).to eq [nil]
        end

        it "references a `*ListFilterInput` from a list-of-text-strings field on the filter type" do
          result = define_schema do |api|
            api.object_type "Widget" do |t|
              t.field "tags", "[String!]!"
            end
          end

          expect(filter_type_from(result, "Widget", include_docs: true).lines.last(7).join).to eq(<<~EOS.chomp)
              """
              Used to filter on the `tags` field.

              When `null` or an empty object is passed, matches all documents.
              """
              tags: StringListFilterInput
            }
          EOS
        end

        it "ignores nullability when deciding whether to references a `*ListFilterInput` from a list-of-scalars field on the filter type" do
          result = define_schema do |api|
            api.object_type "Widget" do |t|
              t.field "tags1", "[String!]!"
              t.field "tags2", "[String!]"
              t.field "tags3", "[String]!"
              t.field "tags4", "[String]"
            end
          end

          expect(filter_type_from(result, "Widget")).to eq(<<~EOS.chomp)
            input WidgetFilterInput {
              #{schema_elements.any_of}: [WidgetFilterInput!]
              #{schema_elements.all_of}: [WidgetFilterInput!]
              #{schema_elements.not}: WidgetFilterInput
              tags1: StringListFilterInput
              tags2: StringListFilterInput
              tags3: StringListFilterInput
              tags4: StringListFilterInput
            }
          EOS
        end

        it "references a `*ListFilterInput` from a paginated list-of-scalars field on the filter type" do
          result = define_schema do |api|
            api.object_type "Widget" do |t|
              t.paginated_collection_field "tags", "String"
            end
          end

          expect(filter_type_from(result, "Widget")).to eq(<<~EOS.chomp)
            input WidgetFilterInput {
              #{schema_elements.any_of}: [WidgetFilterInput!]
              #{schema_elements.all_of}: [WidgetFilterInput!]
              #{schema_elements.not}: WidgetFilterInput
              tags: StringListFilterInput
            }
          EOS
        end

        it "respects a configured type name override when generating the filter field from a `paginated_collection_field`" do
          result = define_schema(type_name_overrides: {LocalTime: "TimeOfDay"}) do |api|
            api.object_type "Widget" do |t|
              t.paginated_collection_field "times", "LocalTime"
            end
          end

          expect(filter_type_from(result, "Widget")).to eq(<<~EOS.chomp)
            input WidgetFilterInput {
              #{schema_elements.any_of}: [WidgetFilterInput!]
              #{schema_elements.all_of}: [WidgetFilterInput!]
              #{schema_elements.not}: WidgetFilterInput
              times: TimeOfDayListFilterInput
            }
          EOS
        end

        it "references a `*ListFilterInput` from a list-of-enums field on the filter type" do
          result = define_schema do |api|
            api.enum_type "Color" do |t|
              t.values "RED", "GREEN", "BLUE"
            end

            api.object_type "Widget" do |t|
              t.field "colors", "[Color!]!"
            end
          end

          expect(filter_type_from(result, "Widget")).to eq(<<~EOS.chomp)
            input WidgetFilterInput {
              #{schema_elements.any_of}: [WidgetFilterInput!]
              #{schema_elements.all_of}: [WidgetFilterInput!]
              #{schema_elements.not}: WidgetFilterInput
              colors: ColorListFilterInput
            }
          EOS
        end

        it "references a `*ListFilterInput` from a list-of-text-strings field on the filter type" do
          result = define_schema do |api|
            api.object_type "Widget" do |t|
              t.field "tags", "[String!]!" do |f|
                f.mapping type: "text"
              end

              t.field "tags_alt", "[String!]!", name_in_index: "tags", graphql_only: true
            end
          end

          expect(filter_type_from(result, "Widget")).to eq(<<~EOS.chomp)
            input WidgetFilterInput {
              #{schema_elements.any_of}: [WidgetFilterInput!]
              #{schema_elements.all_of}: [WidgetFilterInput!]
              #{schema_elements.not}: WidgetFilterInput
              tags: TextListFilterInput
              tags_alt: TextListFilterInput
            }
          EOS
        end

        it "references a `*ListFilterInput` from a list-of-geo-locations field on the filter type since it is a leaf field type in the index" do
          result = define_schema do |api|
            api.object_type "Widget" do |t|
              t.field "locations", "[GeoLocation!]!"
            end
          end

          expect(filter_type_from(result, "Widget")).to eq(<<~EOS.chomp)
            input WidgetFilterInput {
              #{schema_elements.any_of}: [WidgetFilterInput!]
              #{schema_elements.all_of}: [WidgetFilterInput!]
              #{schema_elements.not}: WidgetFilterInput
              locations: GeoLocationListFilterInput
            }
          EOS
        end

        it "omits a filter for a list-of-custom-object-mapping field since we don't know how to support filtering on it" do
          result = define_schema do |api|
            api.object_type "Shape" do |t|
              t.field "type", "String"
              t.field "coordinates", "[Float!]!"
              t.mapping type: "geo_shape"
            end

            api.object_type "Widget" do |t|
              t.field "id", "ID!"
              t.field "shapes", "[Shape!]!"
            end
          end

          expect(filter_type_from(result, "Widget")).to eq(<<~EOS.chomp)
            input WidgetFilterInput {
              #{schema_elements.any_of}: [WidgetFilterInput!]
              #{schema_elements.all_of}: [WidgetFilterInput!]
              #{schema_elements.not}: WidgetFilterInput
              id: IDFilterInput
            }
          EOS
        end

        it "references a `*ListFilterInput` from a list-of-nested-objects field on the filter type since nested documents get separately indexed" do
          result = define_schema do |api|
            api.object_type "Shape" do |t|
              t.field "type", "String"
              t.field "coordinates", "[Float!]!"
            end

            api.object_type "Widget" do |t|
              t.field "id", "ID!"
              t.field "shapes", "[Shape!]!" do |f|
                f.mapping type: "nested"
              end
            end
          end

          expect(filter_type_from(result, "Widget")).to eq(<<~EOS.chomp)
            input WidgetFilterInput {
              #{schema_elements.any_of}: [WidgetFilterInput!]
              #{schema_elements.all_of}: [WidgetFilterInput!]
              #{schema_elements.not}: WidgetFilterInput
              id: IDFilterInput
              shapes: ShapeListFilterInput
            }
          EOS
        end

        it "references the `*FieldsListFilterInput` from a list-of-embedded objects field on the filter type to make `any_satisfy` show up where we want it to" do
          result = define_schema do |api|
            api.object_type "Shape" do |t|
              t.field "type", "String"
              t.field "coordinates", "[Float!]!"
            end

            api.object_type "Widget" do |t|
              t.field "id", "ID!"
              t.field "shapes", "[Shape!]!" do |f|
                f.mapping type: "object"
              end
            end
          end

          expect(filter_type_from(result, "Widget")).to eq(<<~EOS.chomp)
            input WidgetFilterInput {
              #{schema_elements.any_of}: [WidgetFilterInput!]
              #{schema_elements.all_of}: [WidgetFilterInput!]
              #{schema_elements.not}: WidgetFilterInput
              id: IDFilterInput
              shapes: ShapeFieldsListFilterInput
            }
          EOS
        end

        it "references a `*ListFilterInput` from a `paginated_collection_field` that is mapped with `nested`" do
          result = define_schema do |api|
            api.object_type "PlayerSeason" do |t|
              t.field "year", "Int"
            end

            api.object_type "Player" do |t|
              t.paginated_collection_field "seasons", "PlayerSeason" do |f|
                f.mapping type: "nested"
              end
            end

            api.object_type "Team" do |t|
              t.field "id", "ID!"
              t.field "players", "[Player]" do |f|
                f.mapping type: "object"
              end
            end
          end

          expect(fields_list_filter_type_from(result, "Player")).to eq(<<~EOS.strip)
            input PlayerFieldsListFilterInput {
              #{schema_elements.any_of}: [PlayerFieldsListFilterInput!]
              #{schema_elements.all_of}: [PlayerFieldsListFilterInput!]
              #{schema_elements.not}: PlayerFieldsListFilterInput
              seasons: PlayerSeasonListFilterInput
              #{schema_elements.count}: IntFilterInput
            }
          EOS
        end

        it "respects a type name override when generating the `*ListFilterInput` field from a `paginated_collection_field` that is mapped with `nested`" do
          result = define_schema(type_name_overrides: {PlayerSeason: "SeasonForAPlayer"}) do |api|
            api.object_type "PlayerSeason" do |t|
              t.field "year", "Int"
            end

            api.object_type "Player" do |t|
              t.paginated_collection_field "seasons", "PlayerSeason" do |f|
                f.mapping type: "nested"
              end
            end

            api.object_type "Team" do |t|
              t.field "id", "ID!"
              t.field "players", "[Player]" do |f|
                f.mapping type: "object"
              end
            end
          end

          expect(fields_list_filter_type_from(result, "Player")).to eq(<<~EOS.strip)
            input PlayerFieldsListFilterInput {
              #{schema_elements.any_of}: [PlayerFieldsListFilterInput!]
              #{schema_elements.all_of}: [PlayerFieldsListFilterInput!]
              #{schema_elements.not}: PlayerFieldsListFilterInput
              seasons: SeasonForAPlayerListFilterInput
              #{schema_elements.count}: IntFilterInput
            }
          EOS
        end

        describe "`*FieldsListFilterInput` types" do
          it "documents how it differs from other filter types" do
            result = define_schema do |api|
              api.object_type "WidgetOptions" do |t|
                t.field "int", "Int"
              end
            end

            expect(fields_list_filter_type_from(result, "WidgetOptions", include_docs: true).lines.first(8).join).to eq(<<~EOS)
              """
              Input type used to specify filters on a `WidgetOptions` object referenced directly
              or transitively from a list field that has been configured to index each leaf field as
              its own flattened list of values.

              Will match all documents if passed as an empty object (or as `null`).
              """
              input WidgetOptionsFieldsListFilterInput {
            EOS
          end

          it "defines a `*ListFilterInput` field for each scalar or enum field, regardless of it is a list or singleton value field, and regardless of nullability" do
            result = define_schema do |api|
              api.enum_type "Color" do |t|
                t.values "RED", "BLUE", "GREEN"
              end

              api.object_type "WidgetOptions" do |t|
                t.field "single_color1", "Color"
                t.field "single_color2", "Color!"
                t.field "colors1", "[Color]"
                t.field "colors2", "[Color!]"
                t.field "colors3", "[Color]!"
                t.field "colors4", "[Color!]!"
                t.field "single_int1", "Int"
                t.field "single_int2", "Int!"
                t.field "ints1", "[Int]"
                t.field "ints2", "[Int!]"
                t.field "ints3", "[Int]!"
                t.field "ints4", "[Int!]!"
              end
            end

            expect(fields_list_filter_type_from(result, "WidgetOptions")).to eq(<<~EOS.strip)
              input WidgetOptionsFieldsListFilterInput {
                #{schema_elements.any_of}: [WidgetOptionsFieldsListFilterInput!]
                #{schema_elements.all_of}: [WidgetOptionsFieldsListFilterInput!]
                #{schema_elements.not}: WidgetOptionsFieldsListFilterInput
                single_color1: ColorListFilterInput
                single_color2: ColorListFilterInput
                colors1: ColorListFilterInput
                colors2: ColorListFilterInput
                colors3: ColorListFilterInput
                colors4: ColorListFilterInput
                single_int1: IntListFilterInput
                single_int2: IntListFilterInput
                ints1: IntListFilterInput
                ints2: IntListFilterInput
                ints3: IntListFilterInput
                ints4: IntListFilterInput
                #{schema_elements.count}: IntFilterInput
              }
            EOS
          end

          it "defines a `*ListFilterInput` field for each object, regardless of it is a list or singleton value field, and regardless of nullability" do
            result = define_schema do |api|
              api.object_type "WidgetOptions" do |t|
                t.field "size", "Int"
              end

              api.object_type "Widget" do |t|
                t.field "options", "WidgetOptions"
                t.field "embedded_options_list", "[WidgetOptions]" do |f|
                  f.mapping type: "object"
                end
                t.field "nested_options_list", "[WidgetOptions]" do |f|
                  f.mapping type: "nested"
                end
              end
            end

            expect(fields_list_filter_type_from(result, "Widget")).to eq(<<~EOS.strip)
              input WidgetFieldsListFilterInput {
                #{schema_elements.any_of}: [WidgetFieldsListFilterInput!]
                #{schema_elements.all_of}: [WidgetFieldsListFilterInput!]
                #{schema_elements.not}: WidgetFieldsListFilterInput
                options: WidgetOptionsFieldsListFilterInput
                embedded_options_list: WidgetOptionsFieldsListFilterInput
                nested_options_list: WidgetOptionsListFilterInput
                #{schema_elements.count}: IntFilterInput
              }
            EOS
          end

          it "treats `GeoLocation` fields like a scalar field rather than an object field, since it is a leaf field in the index" do
            result = define_schema do |api|
              api.object_type "WidgetOptions" do |t|
                t.field "geo_location", "GeoLocation"
                t.field "geo_locations", "[GeoLocation]"
              end
            end

            expect(fields_list_filter_type_from(result, "WidgetOptions")).to eq(<<~EOS.strip)
              input WidgetOptionsFieldsListFilterInput {
                #{schema_elements.any_of}: [WidgetOptionsFieldsListFilterInput!]
                #{schema_elements.all_of}: [WidgetOptionsFieldsListFilterInput!]
                #{schema_elements.not}: WidgetOptionsFieldsListFilterInput
                geo_location: GeoLocationListFilterInput
                geo_locations: GeoLocationListFilterInput
                #{schema_elements.count}: IntFilterInput
              }
            EOS
          end

          it "omits fields which are not filterable" do
            result = define_schema do |api|
              api.object_type "WidgetOptions" do |t|
                t.field "int1", "Int", filterable: false
                t.field "int2", "Int"
              end
            end

            expect(fields_list_filter_type_from(result, "WidgetOptions")).to eq(<<~EOS.strip)
              input WidgetOptionsFieldsListFilterInput {
                #{schema_elements.any_of}: [WidgetOptionsFieldsListFilterInput!]
                #{schema_elements.all_of}: [WidgetOptionsFieldsListFilterInput!]
                #{schema_elements.not}: WidgetOptionsFieldsListFilterInput
                int2: IntListFilterInput
                #{schema_elements.count}: IntFilterInput
              }
            EOS
          end
        end

        it "forces the user to decide if they want to use `object` or `nested` for the mapping type of a list-of-objects field" do
          expect {
            define_schema do |api|
              api.object_type "WidgetOptions" do |t|
                t.field "int", "Int"
              end

              api.object_type "Widget" do |t|
                t.field "id", "ID!"
                t.field "options", "[WidgetOptions]"
                t.index "widgets"
              end
            end
          }.to raise_error Errors::SchemaError, a_string_including(
            "`Widget.options` is a list-of-objects field, but the mapping type has not been explicitly specified"
          )
        end

        shared_examples_for "a type with subtypes" do |type_def_method|
          it "defines a filter using the set union of the fields of the subtypes" do
            result = define_schema do |api|
              api.object_type "Person" do |t|
                link_subtype_to_supertype(t, "Inventor")
                t.field "name", "String"
                t.field "nationality", "String"
              end

              api.object_type "Company" do |t|
                link_subtype_to_supertype(t, "Inventor")
                t.field "name", "String"
                t.field "stock_ticker", "String"
              end

              api.public_send type_def_method, "Inventor" do |t|
                link_supertype_to_subtypes(t, "Person", "Company")
              end
            end

            # Note: we would like to support filtering on `__typename` but this is invalid according to the
            # GraphQL Spec: http://spec.graphql.org/June2018/#sec-Input-Objects
            # > For each input field of an Input Object type:
            # > 2. The input field must not have a name which begins with the characters "__" (two underscores).
            expect(filter_type_from(result, "Inventor")).to eq(<<~EOS.strip)
              input InventorFilterInput {
                #{schema_elements.any_of}: [InventorFilterInput!]
                #{schema_elements.all_of}: [InventorFilterInput!]
                #{schema_elements.not}: InventorFilterInput
                name: StringFilterInput
                nationality: StringFilterInput
                stock_ticker: StringFilterInput
              }
            EOS
          end

          it "raises a clear error if overlapping fields have different types (meaning we can't define a shared filter field for it)" do
            expect {
              define_schema do |api|
                api.enum_type "ShirtSize" do |t|
                  t.values "S", "M", "L"
                end

                api.enum_type "PantsSize" do |t|
                  t.values "M", "L", "XL"
                end

                api.object_type "Shirt" do |t|
                  link_subtype_to_supertype(t, "ClothingItem")
                  t.field "size", "ShirtSize"
                  t.field "shirt_color", "String"
                end

                api.object_type "Pants" do |t|
                  link_subtype_to_supertype(t, "ClothingItem")
                  t.field "size", "PantsSize"
                  t.field "pants_color", "String"
                end

                api.public_send type_def_method, "ClothingItem" do |t|
                  link_supertype_to_subtypes(t, "Shirt", "Pants")
                end
              end
            }.to raise_error(Errors::SchemaError, a_string_including("Conflicting definitions", "field `size`", "subtypes of `ClothingItem`", "Shirt", "Pants"))
          end

          it "does not raise an error if the difference in type for overlapping fields is just nullable vs non-nullable since filter fields are all nullable anyway" do
            result = define_schema do |api|
              api.enum_type "Size" do |t|
                t.values "S", "M", "L"
              end

              api.object_type "Shirt" do |t|
                link_subtype_to_supertype(t, "ClothingItem")
                t.field "size", "Size!"
                t.field "shirt_color", "String"
              end

              api.object_type "Pants" do |t|
                link_subtype_to_supertype(t, "ClothingItem")
                t.field "size", "Size"
                t.field "pants_color", "String"
              end

              api.public_send type_def_method, "ClothingItem" do |t|
                link_supertype_to_subtypes(t, "Shirt", "Pants")
              end
            end

            expect(filter_type_from(result, "ClothingItem")).to eq(<<~EOS.strip)
              input ClothingItemFilterInput {
                #{schema_elements.any_of}: [ClothingItemFilterInput!]
                #{schema_elements.all_of}: [ClothingItemFilterInput!]
                #{schema_elements.not}: ClothingItemFilterInput
                size: SizeFilterInput
                shirt_color: StringFilterInput
                pants_color: StringFilterInput
              }
            EOS
          end

          it "still raises an error if the difference in type is list vs scalar" do
            expect {
              define_schema do |api|
                api.enum_type "Size" do |t|
                  t.values "S", "M", "L"
                end

                api.object_type "Shirt" do |t|
                  link_subtype_to_supertype(t, "ClothingItem")
                  t.field "size", "Size"
                  t.field "shirt_color", "String"
                end

                api.object_type "Pants" do |t|
                  link_subtype_to_supertype(t, "ClothingItem")
                  t.field "size", "[Size]"
                  t.field "pants_color", "String"
                end

                api.public_send type_def_method, "ClothingItem" do |t|
                  link_supertype_to_subtypes(t, "Shirt", "Pants")
                end
              end
            }.to raise_error(Errors::SchemaError, a_string_including("Conflicting definitions", "field `size`", "subtypes of `ClothingItem`", "Shirt", "Pants"))
          end

          it "still excludes `filterable: false` fields from the generated filter type" do
            result = define_schema do |api|
              api.object_type "Person" do |t|
                link_subtype_to_supertype(t, "Inventor")
                t.field "name", "String"
                t.field "nationality", "String", filterable: false
              end

              api.object_type "Company" do |t|
                link_subtype_to_supertype(t, "Inventor")
                t.field "name", "String"
                t.field "stock_ticker", "String"
              end

              api.public_send type_def_method, "Inventor" do |t|
                link_supertype_to_subtypes(t, "Person", "Company")
              end
            end

            expect(filter_type_from(result, "Inventor")).to eq(<<~EOS.strip)
              input InventorFilterInput {
                #{schema_elements.any_of}: [InventorFilterInput!]
                #{schema_elements.all_of}: [InventorFilterInput!]
                #{schema_elements.not}: InventorFilterInput
                name: StringFilterInput
                stock_ticker: StringFilterInput
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
                t.field "nationality", "String"
              end

              api.object_type "Company" do |t|
                t.implements "Organization"
                t.field "name", "String"
                t.field "stock_ticker", "String"
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

            expect(filter_type_from(result, "Inventor")).to eq(<<~EOS.strip)
              input InventorFilterInput {
                #{schema_elements.any_of}: [InventorFilterInput!]
                #{schema_elements.all_of}: [InventorFilterInput!]
                #{schema_elements.not}: InventorFilterInput
                name: StringFilterInput
                nationality: StringFilterInput
                stock_ticker: StringFilterInput
              }
            EOS
          end
        end
      end
    end
  end
end
