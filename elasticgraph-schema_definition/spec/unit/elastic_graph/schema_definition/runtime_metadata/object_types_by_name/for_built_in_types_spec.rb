# Copyright 2024 - 2026 Block, Inc.
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
          expect(metadata.graphql_fields_by_name.transform_values(&:computation_function)).to eq(
            "approximate_avg" => :avg,
            "approximate_sum" => :sum,
            "exact_sum" => :sum,
            "exact_max" => :max,
            "exact_min" => :min,
            "approximate_distinct_value_count" => :cardinality,
            "approximate_percentile" => :percentile
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
          expect(metadata.graphql_fields_by_name.transform_values(&:computation_function)).to eq(
            "approximate_avg" => :avg,
            "approximate_sum" => :sum,
            "exact_max" => :max,
            "exact_min" => :min,
            "approximate_distinct_value_count" => :cardinality,
            "approximate_percentile" => :percentile
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
          expect(metadata.graphql_fields_by_name.transform_values(&:computation_function)).to eq(
            "approximate_avg" => :avg,
            "approximate_sum" => :sum,
            "exact_sum" => :sum,
            "exact_max" => :max,
            "exact_min" => :min,
            "approximate_distinct_value_count" => :cardinality,
            "approximate_percentile" => :percentile
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
          expect(metadata.graphql_fields_by_name.transform_values(&:computation_function)).to eq(
            "approximate_avg" => :avg,
            "approximate_sum" => :sum,
            "exact_sum" => :sum,
            "approximate_max" => :max,
            "exact_max" => :max,
            "approximate_min" => :min,
            "exact_min" => :min,
            "approximate_distinct_value_count" => :cardinality,
            "approximate_percentile" => :percentile
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
