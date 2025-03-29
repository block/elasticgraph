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
    RSpec.describe "RuntimeMetadata #object_types_by_name on aggregation types derived from indexed types" do
      include_context "object type metadata support"

      it "records the necessary metadata on indexed aggregation types" do
        metadata = object_type_metadata_for "WidgetAggregation" do |s|
          s.object_type "Widget" do |t|
            t.field "id", "ID"
            t.field "size", "Int"
            t.index "widgets"
          end
        end

        expect(metadata.elasticgraph_category).to eq :indexed_aggregation
        expect(metadata.source_type).to eq "Widget"
        expect(metadata.index_definition_names).to eq []
      end

      it "records the necessary metadata on nested sub aggregation types" do
        metadata = object_type_metadata_for "TeamPlayerSubAggregationConnection" do |s|
          s.object_type "Player" do |t|
            t.field "id", "ID!"
            t.field "name", "String"
          end

          s.object_type "Team" do |t|
            t.field "id", "ID!"
            t.field "name", "String"
            t.field "players", "[Player!]!" do |f|
              f.mapping type: "nested"
            end
            t.index "teams"
          end
        end

        expect(metadata.elasticgraph_category).to eq :nested_sub_aggregation_connection
        expect(metadata.index_definition_names).to eq []
      end

      it "dumps the customized `name_in_index` on aggregation grouped by types, too, so that the query engine is made aware of the alternate name" do
        metadata = object_type_metadata_for "WidgetGroupedBy" do |s|
          s.object_type "Widget" do |t|
            t.field "id", "ID"
            t.field "description", "String", name_in_index: "description_index"
            t.index "widgets"
          end
        end

        expect(metadata.graphql_fields_by_name).to eq({
          "description" => graphql_field_with(
            name_in_index: "description_index",
            relation: nil,
            resolver: :object_with_lookahead
          )
        })
      end

      it "dumps the customized `name_in_index` on aggregated values types, too, so that the query engine is made aware of the alternate name" do
        metadata = object_type_metadata_for "WidgetAggregatedValues" do |s|
          s.object_type "Widget" do |t|
            t.field "id", "ID"
            t.field "cost", "Int", name_in_index: "cost_index"
            t.index "widgets"
          end
        end

        expect(metadata.graphql_fields_by_name).to eq({
          "cost" => graphql_field_with(
            name_in_index: "cost_index",
            relation: nil,
            resolver: :object_with_lookahead
          ),
          "id" => graphql_field_with(
            name_in_index: "id",
            relation: nil,
            resolver: :object_with_lookahead
          )
        })
      end

      it "dumps the customized `name_in_index` on sub-aggregation types, too so that the query engine is made aware of the alternate name" do
        team_sub_aggs, team_collections_sub_aggs = object_type_metadata_for(
          "TeamAggregationSubAggregations",
          "TeamAggregationCollectionsSubAggregations"
        ) do |schema|
          schema.object_type "Player" do |t|
            t.field "name", "String"
          end

          schema.object_type "TeamCollections" do |t|
            t.field "players", "[Player!]!", name_in_index: "the_players" do |f|
              f.mapping type: "nested"
            end
          end

          schema.object_type "Team" do |t|
            t.field "id", "ID!"
            t.field "name", "String"
            t.field "collections", "TeamCollections", name_in_index: "collections_in_index"
            t.index "teams"
          end
        end

        expect(team_sub_aggs.graphql_fields_by_name).to eq({
          "collections" => graphql_field_with(name_in_index: "collections_in_index", resolver: :object_with_lookahead)
        })

        expect(team_collections_sub_aggs.graphql_fields_by_name).to eq({
          "players" => graphql_field_with(name_in_index: "the_players", resolver: :object_with_lookahead)
        })
      end
    end
  end
end
