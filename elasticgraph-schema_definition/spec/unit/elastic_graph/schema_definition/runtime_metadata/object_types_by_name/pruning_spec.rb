# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require_relative "object_type_metadata_support"

module ElasticGraph
  module SchemaDefinition
    RSpec.describe "RuntimeMetadata #object_types_by_name--pruning" do
      include_context "object type metadata support"

      it "prunes down the dumped types to ones that have runtime metadata, avoiding dumping a ton of ElasticGraph built-ins (`PageInfo`, etc), but dumping derived graphql types (aggregation, filters) and aggregated value types" do
        results = define_schema do |s|
          s.object_type "Widget" do |t|
            t.field "id", "ID!"
            t.field "options", "WidgetOptions"
            t.field "description", "String", name_in_index: "description_in_index"
            t.index "widgets"
          end

          s.object_type "WidgetOptions" do |t|
            t.field "size", "Int", name_in_index: "size_in_index"
          end

          s.object_type "NoCustomizations" do |t|
            t.field "size", "Int", graphql_only: true
          end
        end

        runtime_metadata = SchemaArtifacts::RuntimeMetadata::Schema.from_hash(results.runtime_metadata.to_dumpable_hash)

        # Note: this list has greatly grown over time. When you make a change causing a new type to be dumped, this'll fail
        # and force you to consider if that new type should be dumped or not. Add types to this as needed for ones that we
        # do want dumped.
        list = %w[
          AggregationCountDetail
          BooleanListFilterInput
          CursorListFilterInput
          DateAggregatedValues
          DateGroupedBy
          DateGroupingGranularityListFilterInput
          DateGroupingTruncationUnitListFilterInput
          DateListFilterInput
          DateTimeAggregatedValues
          DateTimeGroupedBy
          DateTimeGroupingGranularityListFilterInput
          DateTimeGroupingTruncationUnitListFilterInput
          DateTimeListFilterInput
          DateTimeUnitListFilterInput
          DateUnitListFilterInput
          DayOfWeekListFilterInput
          DistanceUnitListFilterInput
          FloatAggregatedValues
          FloatListFilterInput
          GeoLocation
          GeoLocationListFilterInput
          IDListFilterInput
          IntAggregatedValues
          IntListFilterInput
          JsonSafeLongAggregatedValues
          JsonSafeLongListFilterInput
          LocalTimeAggregatedValues
          LocalTimeGroupingTruncationUnitListFilterInput
          LocalTimeListFilterInput
          LocalTimeUnitListFilterInput
          LongStringAggregatedValues
          LongStringListFilterInput
          MatchesQueryAllowedEditsPerTermListFilterInput
          NoCustomizations
          NoCustomizationsAggregatedValues
          NoCustomizationsFieldsListFilterInput
          NoCustomizationsGroupedBy
          NoCustomizationsListFilterInput
          NonNumericAggregatedValues
          PageInfo
          Query
          StringListFilterInput
          TextListFilterInput
          TimeZoneListFilterInput
          UntypedListFilterInput
          Widget
          WidgetAggregatedValues
          WidgetAggregation
          WidgetAggregationConnection
          WidgetAggregationEdge
          WidgetConnection
          WidgetEdge
          WidgetFieldsListFilterInput
          WidgetFilterInput
          WidgetGroupedBy
          WidgetListFilterInput
          WidgetOptions
          WidgetOptionsAggregatedValues
          WidgetOptionsFieldsListFilterInput
          WidgetOptionsFilterInput
          WidgetOptionsGroupedBy
          WidgetOptionsListFilterInput
        ].sort

        expect(runtime_metadata.object_types_by_name.keys).to match_array(list)
      end

      it "excludes derived types that come from a `graphql_only` type so that extensions (like `elasticgraph-apollo`) can define GraphQL-only types" do
        object_types_by_name = define_schema do |s|
          s.object_type "CustomFrameworkObject" do |t|
            t.field "foo", "String"
            t.graphql_only true
          end

          s.scalar_type "CustomFrameworkScalar" do |t|
            t.mapping type: "keyword"
            t.json_schema type: "string"
            t.graphql_only true
          end

          s.enum_type "CustomFrameworkEnum" do |t|
            t.value "FOO"
            t.graphql_only true
          end
        end.runtime_metadata.object_types_by_name

        expect(object_types_by_name.keys.grep(/CustomFramework/)).to contain_exactly("CustomFrameworkObject")
      end
    end
  end
end
