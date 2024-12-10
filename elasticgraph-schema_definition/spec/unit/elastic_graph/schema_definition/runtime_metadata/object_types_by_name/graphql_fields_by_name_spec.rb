# Copyright 2024 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require_relative "object_type_metadata_support"

module ElasticGraph
  module SchemaDefinition
    RSpec.describe "RuntimeMetadata #object_types_by_name #graphql_fields_by_name" do
      include_context "object type metadata support"

      context "on a normal indexed type" do
        it "dumps the `name_in_index` of any fields" do
          metadata = object_type_metadata_for "Widget" do |s|
            s.object_type "Widget" do |t|
              t.field "id", "ID"
              t.field "description", "String", name_in_index: "description_index"
              t.index "widgets"
            end
          end

          expect(metadata.graphql_fields_by_name).to eq({
            "description" => graphql_field_with(
              name_in_index: "description_index",
              relation: nil
            )
          })
        end

        it "dumps the customized `name_in_index` on filter types, too, so that the query engine is made aware of the alternate name" do
          metadata = object_type_metadata_for "WidgetFilterInput" do |s|
            s.object_type "Widget" do |t|
              t.field "id", "ID"
              t.field "description", "String", name_in_index: "description_index"
              t.index "widgets"
            end
          end

          expect(metadata.graphql_fields_by_name).to eq({
            "description" => graphql_field_with(
              name_in_index: "description_index",
              relation: nil
            )
          })
        end

        it "honors `name_in_index` passed to `paginated_collection_field`" do
          metadata = object_types_by_name do |s|
            s.object_type "Widget" do |t|
              t.field "id", "ID"
              t.paginated_collection_field "names", "String", name_in_index: "names2"
              t.index "widgets"
            end
          end

          expected_graphql_fields_by_name = {
            "names" => graphql_field_with(
              name_in_index: "names2",
              relation: nil
            )
          }

          expect(metadata.fetch("Widget").graphql_fields_by_name).to eq(expected_graphql_fields_by_name)
          expect(metadata.fetch("WidgetFilterInput").graphql_fields_by_name).to eq(expected_graphql_fields_by_name)
        end
      end

      context "on an embedded object type" do
        it "dumps the `name_in_index` of any fields" do
          metadata = object_type_metadata_for "Widget" do |s|
            s.object_type "Widget" do |t|
              t.field "description", "String", name_in_index: "description_index"
            end
          end

          expect(metadata.graphql_fields_by_name).to eq({
            "description" => graphql_field_with(
              name_in_index: "description_index",
              relation: nil
            )
          })
        end
      end

      it "dumps the `name_in_index: #{LIST_COUNTS_FIELD}` for all `*ListFilterInput` and `*FieldsListFilterInput` types so that our filter interpreter knows that its for the special `#{LIST_COUNTS_FIELD}` field" do
        results = define_schema do |schema|
          schema.enum_type "Color" do |t|
            t.values "RED", "GREEN", "BLUE"
          end

          schema.scalar_type "Duration" do |t|
            t.mapping type: "keyword"
            t.json_schema type: "string"
          end

          schema.object_type "Options" do |t|
            t.field "size", "Int"
          end

          schema.object_type "GrabBag" do |t|
            t.field "id", "ID!"
            t.index "grabbags"
          end
        end

        list_filter_types = results.graphql_schema_string.scan(/input ((?:\w+)ListFilterInput)\b/).flatten

        # This contains the `*ListFilterInput` type for the types defined above plus all built-in types as of 2023-09-21.
        # It's not expected that this be kept in sync as we add new types to ElasticGraph over time--we just want
        # to verify that we're covering a wide swath of different kinds of types here.
        expected_minimum_list_filter_types = %w[
          BooleanListFilterInput ColorListFilterInput CursorListFilterInput DateListFilterInput DateGroupingGranularityListFilterInput DateTimeListFilterInput
          DateTimeGroupingGranularityListFilterInput DateTimeUnitListFilterInput DistanceUnitListFilterInput DurationListFilterInput FloatListFilterInput
          GeoLocationListFilterInput GrabBagListFilterInput IDListFilterInput IntListFilterInput JsonSafeLongListFilterInput LocalTimeListFilterInput
          LongStringListFilterInput OptionsListFilterInput StringListFilterInput TextListFilterInput TimeZoneListFilterInput UntypedListFilterInput
          GrabBagFieldsListFilterInput OptionsFieldsListFilterInput
        ]

        expect(list_filter_types).to include(*expected_minimum_list_filter_types)

        object_types_by_name = results.runtime_metadata.object_types_by_name
        has_runtime_metadata, missing_runtime_metadata = list_filter_types.partition { |type| object_types_by_name.key?(type) }

        # All `*ListFilterInput` types should be in runtime metadata so that their `count` field can have `name_in_index = __counts`.
        expect(missing_runtime_metadata).to be_empty

        missing_count_name_in_index = has_runtime_metadata.reject do |type|
          # :nocov: -- some branches of the line below are only covered when the test fails.
          object_types_by_name.fetch(type).graphql_fields_by_name.dig("count")&.name_in_index == LIST_COUNTS_FIELD
          # :nocov:
        end

        expect(missing_count_name_in_index).to be_empty
      end

      it "omits `name_in_index: #{LIST_COUNTS_FIELD}` when there is a user-defined field named `count` to avoid overriding the field that gets generated for the user-defined field" do
        count_type_meta, count1_type_meta = object_type_metadata_for "CountTypeFieldsListFilterInput", "Count1TypeFieldsListFilterInput" do |schema|
          schema.object_type "CountType" do |t|
            t.field "count", "Int"
          end

          schema.object_type "Count1Type" do |t|
            t.field "count1", "Int"
          end

          schema.object_type "RootType" do |t|
            t.field "id", "ID!"
            t.field "list", "[CountType!]!" do |f|
              f.mapping type: "object"
            end
            t.field "list1", "[Count1Type!]!" do |f|
              f.mapping type: "object"
            end
            t.index "roots"
          end
        end

        # Metadata is not dumped for this case because `count` is a normal, user-defined field without a custom `name_in_index`.
        expect(count_type_meta).to be nil
        # ...but it's still dumped for this one because it's our special LIST_COUNTS_FIELD.
        expect(count1_type_meta.graphql_fields_by_name["count"].name_in_index).to eq LIST_COUNTS_FIELD
        expect(logged_output).to include(
          "WARNING: Since a `CountType.count` field exists, ElasticGraph is not able to\n" \
          "define its typical `CountTypeFieldsListFilterInput.count` field"
        )
      end
    end
  end
end