# Copyright 2024 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require_relative "graphql_schema_spec_support"

module ElasticGraph
  module SchemaDefinition
    RSpec.describe "GraphQL schema generation", "#scalar_type" do
      include_context "GraphQL schema spec support"

      with_both_casing_forms do
        it "generates the SDL for a custom scalar type" do
          result = scalar_type "BigInt" do |t|
            t.mapping type: "long"
            t.json_schema type: "integer"
          end

          expect(type_def_from(result, "BigInt")).to eq(<<~EOS.strip)
            scalar BigInt
          EOS
        end

        it "requires the `mapping` to be specified so we know how to index it in the datastore" do
          expect {
            scalar_type "BigInt" do |t|
              t.json_schema type: "integer"
            end
          }.to raise_error Errors::SchemaError, a_string_including("BigInt", "lacks `mapping`")
        end

        it "requires the `json_schema` to be specified so we know how it should be encoded in an ingested event" do
          expect {
            scalar_type "BigInt" do |t|
              t.mapping type: "long"
            end
          }.to raise_error Errors::SchemaError, a_string_including("BigInt", "lacks `json_schema`")
        end

        it "requires a `type` be specified on the `mapping` since we can't guess what the mapping type should be" do
          expect {
            scalar_type "BigInt" do |t|
              t.json_schema type: "integer"
              t.mapping null_value: 0
            end
          }.to raise_error Errors::SchemaError, a_string_including("BigInt", "mapping", "type:")
        end

        it "respects a configured type name override" do
          result = define_schema(type_name_overrides: {"BigInt" => "LargeNumber"}) do |schema|
            schema.object_type "Widget" do |t|
              t.paginated_collection_field "nums", "BigInt"
            end

            schema.scalar_type "BigInt" do |t|
              t.mapping type: "long"
              t.json_schema type: "integer"
            end
          end

          expect(type_def_from(result, "BigInt")).to eq nil
          expect(type_def_from(result, "LargeNumber")).to eq("scalar LargeNumber")

          expect(type_def_from(result, "LargeNumberFilterInput")).not_to eq nil
          expect(type_def_from(result, "LargeNumberConnection")).not_to eq nil
          expect(type_def_from(result, "LargeNumberEdge")).not_to eq nil

          # Verify that there are _no_ `BigInt` types defined
          expect(result.lines.grep(/BigInt/)).to be_empty
        end

        it "allows additional directives to be defined on the scalar" do
          result = define_schema do |schema|
            schema.raw_sdl "directive @meta(since_date: String = null, author: String = null) on SCALAR"

            schema.scalar_type "BigInt" do |t|
              t.mapping type: "long"
              t.json_schema type: "integer"
              t.directive "meta", since_date: "2021-08-01"
              t.directive "meta", author: "John"
            end
          end

          expect(type_def_from(result, "BigInt")).to eq(<<~EOS.strip)
            scalar BigInt @meta(since_date: "2021-08-01") @meta(author: "John")
          EOS
        end

        it "allows documentation to be defined on the scalar" do
          result = scalar_type "BigInt" do |t|
            t.mapping type: "long"
            t.json_schema type: "integer"
            t.documentation "A number that exceeds the normal `Int` max."
          end

          expect(type_def_from(result, "BigInt", include_docs: true)).to eq(<<~EOS.strip)
            """
            A number that exceeds the normal `Int` max.
            """
            scalar BigInt
          EOS
        end

        it "defines a filter type with `any_of` and `equal_to_any_of` for a mapping type that can't efficiently support range queries" do
          result = scalar_type "FullText" do |t|
            t.mapping type: "text"
            t.json_schema type: "string"
          end

          expect(filter_type_from(result, "FullText")).to eq(<<~EOS.strip)
            input FullTextFilterInput {
              #{schema_elements.any_of}: [FullTextFilterInput!]
              #{schema_elements.not}: FullTextFilterInput
              #{schema_elements.equal_to_any_of}: [FullText]
            }
          EOS
        end

        it "defines a filter type with `any_of`, `equal_to_any_of`, and comparison operators for a numeric mapping type that can efficiently support range queries" do
          result = scalar_type "Short" do |t|
            t.mapping type: "short"
            t.json_schema type: "integer"
          end

          expect(filter_type_from(result, "Short")).to eq(<<~EOS.strip)
            input ShortFilterInput {
              #{schema_elements.any_of}: [ShortFilterInput!]
              #{schema_elements.not}: ShortFilterInput
              #{schema_elements.equal_to_any_of}: [Short]
              #{schema_elements.gt}: Short
              #{schema_elements.gte}: Short
              #{schema_elements.lt}: Short
              #{schema_elements.lte}: Short
            }
          EOS
        end

        it "defines a filter type with `any_of`, `equal_to_any_of`, and comparison operators for a date mapping type that can efficiently support range queries" do
          result = scalar_type "CalendarDate" do |t|
            t.mapping type: "date"
            t.json_schema type: "string"
          end

          expect(filter_type_from(result, "CalendarDate")).to eq(<<~EOS.strip)
            input CalendarDateFilterInput {
              #{schema_elements.any_of}: [CalendarDateFilterInput!]
              #{schema_elements.not}: CalendarDateFilterInput
              #{schema_elements.equal_to_any_of}: [CalendarDate]
              #{schema_elements.gt}: CalendarDate
              #{schema_elements.gte}: CalendarDate
              #{schema_elements.lt}: CalendarDate
              #{schema_elements.lte}: CalendarDate
            }
          EOS
        end

        it "defines a `*ListFilterInput` type so that lists of the custom scalar type can be filtered on" do
          result = scalar_type "Short" do |t|
            t.mapping type: "short"
            t.json_schema type: "integer"
          end

          expect(list_filter_type_from(result, "Short", include_docs: true)).to eq(<<~EOS.strip)
            """
            Input type used to specify filters on `[Short]` fields.

            Will match all documents if passed as an empty object (or as `null`).
            """
            input ShortListFilterInput {
              """
              Matches records where any of the provided sub-filters evaluate to true.
              This works just like an OR operator in SQL.

              When `null` is passed, matches all documents.
              When an empty list is passed, this part of the filter matches no documents.
              """
              #{schema_elements.any_of}: [ShortListFilterInput!]
              """
              Matches records where the provided sub-filter evaluates to false.
              This works just like a NOT operator in SQL.

              When `null` or an empty object is passed, matches no documents.
              """
              #{schema_elements.not}: ShortListFilterInput
              """
              Matches records where any of the list elements match the provided sub-filter.

              When `null` or an empty object is passed, matches all documents.
              """
              #{schema_elements.any_satisfy}: ShortListElementFilterInput
              """
              Matches records where all of the provided sub-filters evaluate to true. This works just like an AND operator in SQL.

              Note: multiple filters are automatically ANDed together. This is only needed when you have multiple filters that can't
              be provided on a single `ShortListFilterInput` input because of collisions between key names. For example, if you want to provide
              multiple `#{schema_elements.any_satisfy}: ...` filters, you could do `#{schema_elements.all_of}: [{#{schema_elements.any_satisfy}: ...}, {#{schema_elements.any_satisfy}: ...}]`.

              When `null` or an empty list is passed, matches all documents.
              """
              #{schema_elements.all_of}: [ShortListFilterInput!]
              """
              Used to filter on the number of non-null elements in this list field.

              When `null` or an empty object is passed, matches all documents.
              """
              count: IntFilterInput
            }
          EOS
        end

        it "documents each filter field" do
          result = scalar_type "Byte" do |t|
            t.mapping type: "byte"
            t.json_schema type: "integer"
          end

          expect(filter_type_from(result, "Byte", include_docs: true)).to eq(<<~EOS.strip)
            """
            Input type used to specify filters on `Byte` fields.

            Will match all documents if passed as an empty object (or as `null`).
            """
            input ByteFilterInput {
              """
              Matches records where any of the provided sub-filters evaluate to true.
              This works just like an OR operator in SQL.

              When `null` is passed, matches all documents.
              When an empty list is passed, this part of the filter matches no documents.
              """
              #{schema_elements.any_of}: [ByteFilterInput!]
              """
              Matches records where the provided sub-filter evaluates to false.
              This works just like a NOT operator in SQL.

              When `null` or an empty object is passed, matches no documents.
              """
              #{schema_elements.not}: ByteFilterInput
              """
              Matches records where the field value is equal to any of the provided values.
              This works just like an IN operator in SQL.

              When `null` is passed, matches all documents. When an empty list is passed,
              this part of the filter matches no documents. When `null` is passed in the
              list, this part of the filter matches records where the field value is `null`.
              """
              #{schema_elements.equal_to_any_of}: [Byte]
              """
              Matches records where the field value is greater than (>) the provided value.

              When `null` is passed, matches all documents.
              """
              #{schema_elements.gt}: Byte
              """
              Matches records where the field value is greater than or equal to (>=) the provided value.

              When `null` is passed, matches all documents.
              """
              #{schema_elements.gte}: Byte
              """
              Matches records where the field value is less than (<) the provided value.

              When `null` is passed, matches all documents.
              """
              #{schema_elements.lt}: Byte
              """
              Matches records where the field value is less than or equal to (<=) the provided value.

              When `null` is passed, matches all documents.
              """
              #{schema_elements.lte}: Byte
            }
          EOS
        end

        it "raises a clear error when the type name is not formatted correctly" do
          expect {
            scalar_type("Invalid.Name") {}
          }.to raise_invalid_graphql_name_error_for("Invalid.Name")
        end

        def scalar_type(...)
          define_schema do |api|
            api.scalar_type(...)
          end
        end
      end
    end
  end
end
