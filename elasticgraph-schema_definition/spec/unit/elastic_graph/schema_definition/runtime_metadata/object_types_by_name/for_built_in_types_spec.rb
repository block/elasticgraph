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
    RSpec.describe "RuntimeMetadata #object_types_by_name for built-in types" do
      include_context "object type metadata support"

      context "`AggregatedValues` types" do
        it "includes aggregation functions on `IntAggregatedValues` fields" do
          metadata = object_type_metadata_for "IntAggregatedValues" do |s|
            s.object_type "Widget" do |t|
              t.field "id", "ID"
              t.field "size", "Int"
              t.index "widgets"
            end
          end

          expect(metadata.elasticgraph_category).to eq :scalar_aggregated_values
          expect(metadata.graphql_fields_by_name.transform_values(&:computation_detail)).to eq(
            "approximate_avg" => agg_detail_of(:avg, nil),
            "approximate_sum" => agg_detail_of(:sum, 0),
            "exact_sum" => agg_detail_of(:sum, 0),
            "exact_max" => agg_detail_of(:max, nil),
            "exact_min" => agg_detail_of(:min, nil),
            "approximate_distinct_value_count" => agg_detail_of(:cardinality, 0)
          )
        end

        it "includes aggregation functions on `FloatAggregatedValues` fields" do
          metadata = object_type_metadata_for "FloatAggregatedValues" do |s|
            s.object_type "Widget" do |t|
              t.field "id", "ID"
              t.field "amount", "Float"
              t.index "widgets"
            end
          end

          expect(metadata.elasticgraph_category).to eq :scalar_aggregated_values
          expect(metadata.graphql_fields_by_name.transform_values(&:computation_detail)).to eq(
            "approximate_avg" => agg_detail_of(:avg, nil),
            "approximate_sum" => agg_detail_of(:sum, 0),
            "exact_max" => agg_detail_of(:max, nil),
            "exact_min" => agg_detail_of(:min, nil),
            "approximate_distinct_value_count" => agg_detail_of(:cardinality, 0)
          )
        end

        it "includes aggregation functions on `JsonSafeLongAggregatedValues` fields" do
          metadata = object_type_metadata_for "JsonSafeLongAggregatedValues" do |s|
            s.object_type "Widget" do |t|
              t.field "id", "ID"
              t.field "size", "JsonSafeLong"
              t.index "widgets"
            end
          end

          expect(metadata.elasticgraph_category).to eq :scalar_aggregated_values
          expect(metadata.graphql_fields_by_name.transform_values(&:computation_detail)).to eq(
            "approximate_avg" => agg_detail_of(:avg, nil),
            "approximate_sum" => agg_detail_of(:sum, 0),
            "exact_sum" => agg_detail_of(:sum, 0),
            "exact_max" => agg_detail_of(:max, nil),
            "exact_min" => agg_detail_of(:min, nil),
            "approximate_distinct_value_count" => agg_detail_of(:cardinality, 0)
          )
        end

        it "includes aggregation functions on `LongStringAggregatedValues` fields" do
          metadata = object_type_metadata_for "LongStringAggregatedValues" do |s|
            s.object_type "Widget" do |t|
              t.field "id", "ID"
              t.field "size", "LongString"
              t.index "widgets"
            end
          end

          expect(metadata.elasticgraph_category).to eq :scalar_aggregated_values
          expect(metadata.graphql_fields_by_name.transform_values(&:computation_detail)).to eq(
            "approximate_avg" => agg_detail_of(:avg, nil),
            "approximate_sum" => agg_detail_of(:sum, 0),
            "exact_sum" => agg_detail_of(:sum, 0),
            "approximate_max" => agg_detail_of(:max, nil),
            "exact_max" => agg_detail_of(:max, nil),
            "approximate_min" => agg_detail_of(:min, nil),
            "exact_min" => agg_detail_of(:min, nil),
            "approximate_distinct_value_count" => agg_detail_of(:cardinality, 0)
          )
        end
      end

      context "date grouped by objects" do
        it "sets `elasticgraph_category = :date_grouped_by_object` on the `DateGroupedBy` type" do
          metadata = object_type_metadata_for "DateGroupedBy" do |s|
            s.object_type "Widget" do |t|
              t.field "id", "ID"
              t.field "created_at", "DateTime"
              t.index "widgets"
            end
          end

          expect(metadata.elasticgraph_category).to eq :date_grouped_by_object
        end

        it "sets `elasticgraph_category = :date_grouped_by_object` on the `DateTimeGroupedBy` type" do
          metadata = object_type_metadata_for "DateTimeGroupedBy" do |s|
            s.object_type "Widget" do |t|
              t.field "id", "ID"
              t.field "created_at", "DateTime"
              t.index "widgets"
            end
          end

          expect(metadata.elasticgraph_category).to eq :date_grouped_by_object
        end
      end

      def agg_detail_of(function, empty_bucket_value)
        SchemaArtifacts::RuntimeMetadata::ComputationDetail.new(
          function: function,
          empty_bucket_value: empty_bucket_value
        )
      end

      prepend Module.new {
        def object_type_metadata_for(...)
          super(...).tap do |metadata|
            # All built-in return types should be graphql-only.
            expect(metadata.graphql_only_return_type).to eq true
          end
        end
      }
    end
  end
end
