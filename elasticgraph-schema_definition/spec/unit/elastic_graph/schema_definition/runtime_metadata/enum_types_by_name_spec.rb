# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require_relative "runtime_metadata_support"

module ElasticGraph
  module SchemaDefinition
    RSpec.describe "RuntimeMetadata #enum_types_by_name" do
      include_context "RuntimeMetadata support"

      it "dumps sort info for sort enum types" do
        metadata = enum_type_metadata_for "WidgetSortOrderInput" do |s|
          s.object_type "Widget" do |t|
            t.field "id", "ID!"
            t.field "name", "String"
            t.index "widgets"
          end
        end

        expect(metadata.values_by_name.transform_values(&:sort_field)).to eq(
          "id_ASC" => sort_field_with(field_path: "id", direction: :asc),
          "id_DESC" => sort_field_with(field_path: "id", direction: :desc),
          "name_ASC" => sort_field_with(field_path: "name", direction: :asc),
          "name_DESC" => sort_field_with(field_path: "name", direction: :desc)
        )
      end

      it "dumps `DistanceUnit` metadata" do
        metadata = enum_type_metadata_for "DistanceUnit", expect_matching_input: true

        expect(metadata.values_by_name.transform_values(&:datastore_abbreviation)).to eq(
          "MILE" => :mi,
          "YARD" => :yd,
          "FOOT" => :ft,
          "INCH" => :in,
          "KILOMETER" => :km,
          "METER" => :m,
          "CENTIMETER" => :cm,
          "MILLIMETER" => :mm,
          "NAUTICAL_MILE" => :nmi
        )
      end

      it "dumps `DateTimeUnit` metadata" do
        metadata = enum_type_metadata_for "DateTimeUnit", expect_matching_input: true

        expect(metadata.values_by_name.transform_values(&:datastore_abbreviation)).to eq(
          "DAY" => :d,
          "HOUR" => :h,
          "MILLISECOND" => :ms,
          "MINUTE" => :m,
          "SECOND" => :s
        )

        expect(metadata.values_by_name.transform_values(&:datastore_value)).to eq(
          "DAY" => 86_400_000,
          "HOUR" => 3_600_000,
          "MILLISECOND" => 1,
          "MINUTE" => 60_000,
          "SECOND" => 1_000
        )
      end

      it "dumps `DateUnit` metadata" do
        metadata = enum_type_metadata_for "DateUnit", expect_matching_input: true

        expect(metadata.values_by_name.transform_values(&:datastore_abbreviation)).to eq(
          "DAY" => :d
        )

        expect(metadata.values_by_name.transform_values(&:datastore_value)).to eq(
          "DAY" => 86_400_000
        )
      end

      it "dumps `LocalTimeUnit` metadata" do
        metadata = enum_type_metadata_for "LocalTimeUnit", expect_matching_input: true

        expect(metadata.values_by_name.transform_values(&:datastore_abbreviation)).to eq(
          "HOUR" => :h,
          "MILLISECOND" => :ms,
          "MINUTE" => :m,
          "SECOND" => :s
        )

        expect(metadata.values_by_name.transform_values(&:datastore_value)).to eq(
          "HOUR" => 3_600_000,
          "MILLISECOND" => 1,
          "MINUTE" => 60_000,
          "SECOND" => 1_000
        )
      end

      it "respects enum value name overrides" do
        metadata = enum_type_metadata_for "DistanceUnit", expect_matching_input: true, enum_value_overrides_by_type: {
          DistanceUnit: {MILE: "MI", YARD: "YD"}
        }

        expect(metadata.values_by_name.transform_values(&:datastore_abbreviation)).to include(
          "MI" => :mi,
          "YD" => :yd,
          "FOOT" => :ft # demonstrate one that's not overridden
        )

        expect(metadata.values_by_name.transform_values(&:alternate_original_name)).to include(
          "MI" => "MILE",
          "YD" => "YARD",
          "FOOT" => nil # demonstrate one that's not overridden
        )
      end

      it "is not dumped for any other types of enums (including user-defined ones) since there is no runtime metadata to store for them" do
        results = define_schema do |s|
          s.enum_type "Color" do |t|
            t.values "RED", "BLUE", "GREEN"
          end

          s.object_type "Widget" do |t|
            t.field "id", "ID!"
            t.field "name", "String"
            t.field "color", "Color"
            t.index "widgets"
          end
        end

        runtime_metadata = SchemaArtifacts::RuntimeMetadata::Schema.from_hash(results.runtime_metadata.to_dumpable_hash)
        expect(runtime_metadata.enum_types_by_name.keys).to contain_exactly(
          "DateGroupingTruncationUnit", "DateGroupingTruncationUnitInput",
          "DateTimeGroupingTruncationUnit", "DateTimeGroupingTruncationUnitInput",
          "DateTimeUnit", "DateTimeUnitInput",
          "DateUnit", "DateUnitInput",
          "DistanceUnit", "DistanceUnitInput",
          "LocalTimeGroupingTruncationUnit", "LocalTimeGroupingTruncationUnitInput",
          "LocalTimeUnit", "LocalTimeUnitInput",
          "MatchesQueryAllowedEditsPerTerm", "MatchesQueryAllowedEditsPerTermInput",
          "WidgetSortOrderInput"
        )
      end

      it "uses dot-separated paths for nested sort fields" do
        metadata = enum_type_metadata_for "WidgetSortOrderInput" do |s|
          s.object_type "WidgetOptions" do |t|
            t.field "size", "Int"
            t.field "color", "String"
          end

          s.object_type "Widget" do |t|
            t.field "id", "ID!"
            t.field "options", "WidgetOptions"
            t.index "widgets"
          end
        end

        expect(metadata.values_by_name.transform_values(&:sort_field)).to include(
          "options_size_ASC" => sort_field_with(field_path: "options.size", direction: :asc),
          "options_size_DESC" => sort_field_with(field_path: "options.size", direction: :desc),
          "options_color_ASC" => sort_field_with(field_path: "options.color", direction: :asc),
          "options_color_DESC" => sort_field_with(field_path: "options.color", direction: :desc)
        )
      end

      it "uses a field's `name_in_index` in the sort field path" do
        metadata = enum_type_metadata_for "WidgetSortOrderInput" do |s|
          s.object_type "WidgetOptions" do |t|
            t.field "size", "Int", name_in_index: "size2"
          end

          s.object_type "Widget" do |t|
            t.field "id", "ID!"
            t.field "options", "WidgetOptions", name_in_index: "options2"
            t.index "widgets"
          end
        end

        expect(metadata.values_by_name.transform_values(&:sort_field)).to include(
          "options_size_ASC" => sort_field_with(field_path: "options2.size2", direction: :asc),
          "options_size_DESC" => sort_field_with(field_path: "options2.size2", direction: :desc)
        )
      end

      it "omits unsortable fields" do
        metadata = enum_type_metadata_for "WidgetSortOrderInput" do |s|
          s.object_type "Widget" do |t|
            t.field "id", "ID!"
            t.field "name", "String", sortable: false
            t.index "widgets"
          end
        end

        expect(metadata.values_by_name.transform_values(&:sort_field)).to eq(
          "id_ASC" => sort_field_with(field_path: "id", direction: :asc),
          "id_DESC" => sort_field_with(field_path: "id", direction: :desc)
        )
      end

      def enum_type_metadata_for(name, expect_matching_input: false, **schema_options, &block)
        enum_types_by_name = define_schema(**schema_options, &block).runtime_metadata.enum_types_by_name

        enum_types_by_name[name].tap do |metadata|
          if expect_matching_input
            input_metadata = enum_types_by_name["#{name}Input"]
            expect(input_metadata).to eq(metadata)
          end
        end
      end
    end
  end
end
