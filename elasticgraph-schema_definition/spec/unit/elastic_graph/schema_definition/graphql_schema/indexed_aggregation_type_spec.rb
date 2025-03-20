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
    RSpec.describe "GraphQL schema generation", "an indexed `*Aggregation` type" do
      include_context "GraphQL schema spec support"

      with_both_casing_forms do
        it "is defined for an indexed object type" do
          results = define_schema do |schema|
            schema.object_type "Widget" do |t|
              t.field "id", "ID"
              t.field "name", "String"
              t.field "cost", "Int"
              t.index "widgets"
            end
          end

          expect(aggregation_type_from(results, "Widget", include_docs: true)).to eq(<<~EOS.strip)
            """
            Return type representing a bucket of `Widget` documents for an aggregations query.
            """
            type WidgetAggregation {
              """
              Used to specify the `Widget` fields to group by. The returned values identify each aggregation bucket.
              """
              #{schema_elements.grouped_by}: WidgetGroupedBy
              """
              The count of `Widget` documents in an aggregation bucket.
              """
              count: JsonSafeLong!
              """
              Provides computed aggregated values over all `Widget` documents in an aggregation bucket.
              """
              #{schema_elements.aggregated_values}: WidgetAggregatedValues
            }
          EOS
        end

        it "includes a `sub_aggregations` field when the indexed type has `nested` fields" do
          results = define_schema do |schema|
            schema.object_type "Player" do |t|
              t.field "name", "String"
            end

            schema.object_type "Team" do |t|
              t.field "id", "ID!"
              t.field "name", "String"
              t.field "players", "[Player!]!" do |f|
                f.mapping type: "nested"
              end
              t.index "teams"
            end
          end

          expect(aggregation_type_from(results, "Team", include_docs: true)).to eq(<<~EOS.strip)
            """
            Return type representing a bucket of `Team` documents for an aggregations query.
            """
            type TeamAggregation {
              """
              Used to specify the `Team` fields to group by. The returned values identify each aggregation bucket.
              """
              #{schema_elements.grouped_by}: TeamGroupedBy
              """
              The count of `Team` documents in an aggregation bucket.
              """
              #{schema_elements.count}: JsonSafeLong!
              """
              Provides computed aggregated values over all `Team` documents in an aggregation bucket.
              """
              #{schema_elements.aggregated_values}: TeamAggregatedValues
              """
              Used to perform sub-aggregations of `TeamAggregation` data.
              """
              #{schema_elements.sub_aggregations}: TeamAggregationSubAggregations
            }
          EOS
        end

        it "is defined for an indexed union type" do
          results = define_schema do |schema|
            schema.object_type "Widget" do |t|
              t.field "id", "ID"
              t.field "name", "String"
              t.field "cost", "Int"
            end

            schema.union_type "Entity" do |t|
              t.subtype "Widget"
              t.index "entities"
            end
          end

          expect(aggregation_type_from(results, "Entity")).to eq(<<~EOS.strip)
            type EntityAggregation {
              #{schema_elements.grouped_by}: EntityGroupedBy
              count: JsonSafeLong!
              #{schema_elements.aggregated_values}: EntityAggregatedValues
            }
          EOS
        end

        it "is defined for an indexed interface type" do
          results = define_schema do |schema|
            schema.object_type "Widget" do |t|
              t.implements "Named"
              t.field "id", "ID"
              t.field "name", "String"
              t.field "cost", "Int"
            end

            schema.interface_type "Named" do |t|
              t.field "name", "String"
              t.index "named"
            end
          end

          expect(aggregation_type_from(results, "Named")).to eq(<<~EOS.strip)
            type NamedAggregation {
              #{schema_elements.grouped_by}: NamedGroupedBy
              count: JsonSafeLong!
              #{schema_elements.aggregated_values}: NamedAggregatedValues
            }
          EOS
        end

        it "is not defined for an object type that is not indexed" do
          results = define_schema do |schema|
            schema.object_type "Widget" do |t|
              t.field "id", "ID"
              t.field "name", "String"
              t.field "cost", "Int"
            end
          end

          expect(aggregation_type_from(results, "Widget")).to eq nil
        end

        it "is not defined for a union type that is not indexed" do
          results = define_schema do |schema|
            schema.object_type "Widget" do |t|
              t.field "id", "ID"
              t.field "name", "String"
              t.field "cost", "Int"
            end

            schema.union_type "Entity" do |t|
              t.subtype "Widget"
            end
          end

          expect(aggregation_type_from(results, "Entity")).to eq(nil)
        end

        it "is not defined for an interface type that is not indexed" do
          results = define_schema do |schema|
            schema.object_type "Widget" do |t|
              t.implements "Named"
              t.field "id", "ID"
              t.field "name", "String"
              t.field "cost", "Int"
            end

            schema.interface_type "Named" do |t|
              t.field "name", "String"
            end
          end

          expect(aggregation_type_from(results, "Named")).to eq(nil)
        end

        it "omits the `grouped_by` field if there are no fields to group by" do
          results = define_schema do |schema|
            schema.object_type "Widget" do |t|
              t.field "id", "ID" # id is automatically not groupable, because it uniquely identifies each document!
              t.field "cost", "Int", groupable: false
              t.index "widgets"
            end
          end

          expect(aggregation_type_from(results, "Widget")).to eq(<<~EOS.strip)
            type WidgetAggregation {
              count: JsonSafeLong!
              #{schema_elements.aggregated_values}: WidgetAggregatedValues
            }
          EOS
        end

        it "omits the `aggregated_values` field if there are no fields to aggregate" do
          results = define_schema do |schema|
            schema.object_type "Widget" do |t|
              t.field "id", "ID", aggregatable: false
              t.field "name", "String", aggregatable: false
              t.index "widgets"
            end
          end

          expect(aggregation_type_from(results, "Widget")).to eq(<<~EOS.strip)
            type WidgetAggregation {
              #{schema_elements.grouped_by}: WidgetGroupedBy
              count: JsonSafeLong!
            }
          EOS
        end

        it "has only the `count` field if no fields are groupable or aggregatable" do
          results = define_schema do |schema|
            schema.object_type "Widget" do |t|
              t.field "id", "ID", aggregatable: false, groupable: false
              t.index "widgets"
            end
          end

          expect(aggregation_type_from(results, "Widget")).to eq(<<~EOS.strip)
            type WidgetAggregation {
              count: JsonSafeLong!
            }
          EOS
        end

        it "also defines the `AggregationConnection` and `AggregationEdge` types to support relay pagination" do
          results = define_schema do |schema|
            schema.object_type "Widget" do |t|
              t.field "id", "ID"
              t.field "name", "String"
              t.field "cost", "Int"
              t.index "widgets"
            end
          end

          expect(aggregation_connection_type_from(results, "Widget", include_docs: true)).to eq(<<~EOS.strip)
            """
            Represents a paginated collection of `WidgetAggregation` results.

            See the [Relay GraphQL Cursor Connections
            Specification](https://relay.dev/graphql/connections.htm#sec-Connection-Types) for more info.
            """
            type WidgetAggregationConnection {
              """
              Wraps a specific `WidgetAggregation` to pair it with its pagination cursor.
              """
              edges: [WidgetAggregationEdge!]!
              """
              The list of `WidgetAggregation` results.
              """
              nodes: [WidgetAggregation!]!
              """
              Provides pagination-related information.
              """
              #{schema_elements.page_info}: PageInfo!
            }
          EOS

          expect(aggregation_edge_type_from(results, "Widget", include_docs: true)).to eq(<<~EOS.strip)
            """
            Represents a specific `WidgetAggregation` in the context of a `WidgetAggregationConnection`,
            providing access to both the `WidgetAggregation` and a pagination `Cursor`.

            See the [Relay GraphQL Cursor Connections
            Specification](https://relay.dev/graphql/connections.htm#sec-Edge-Types) for more info.
            """
            type WidgetAggregationEdge {
              """
              The `WidgetAggregation` of this edge.
              """
              node: WidgetAggregation
              """
              The `Cursor` of this `WidgetAggregation`. This can be passed in the next query as
              a `before` or `after` argument to continue paginating from this `WidgetAggregation`.
              """
              cursor: Cursor
            }
          EOS
        end
      end
    end
  end
end
