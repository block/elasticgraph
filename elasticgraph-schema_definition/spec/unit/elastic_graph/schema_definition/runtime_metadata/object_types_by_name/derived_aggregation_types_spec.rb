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
            resolver: configured_graphql_resolver(:object_with_lookahead)
          )
        })
      end

      it "dumps the type name of the backing leaf field on object grouped by fields backed by a leaf index field" do
        grouping_field_backed_by = ->(name_in_index) { ->(f) { f.customize_grouped_by_field { |gbf| gbf.name_in_index = name_in_index } } }

        metadata = object_type_metadata_for "WidgetGroupedBy" do |s|
          s.enum_type "Color" do |t|
            t.value "RED"
          end

          s.object_type "Money" do |t|
            t.field "amount_cents", "Int"
          end

          s.object_type "WidgetOptions" do |t|
            t.field "size", "Int"
          end

          s.object_type "Widget" do |t|
            t.field "id", "ID"
            t.field "color", "Color"
            t.field "name", "String"
            t.field "is_draft", "Boolean"
            t.field "options", "WidgetOptions"
            t.field "created_at", "DateTime"
            t.paginated_collection_field "tags", "String", singular: "tag"
            t.field "by_color", "Money", &grouping_field_backed_by.call("color")
            t.field "by_name", "Money", &grouping_field_backed_by.call("name")
            t.field "by_size", "Money", &grouping_field_backed_by.call("options.size")
            t.field "by_is_draft", "Money", &grouping_field_backed_by.call("is_draft")
            t.field "by_options", "Money", &grouping_field_backed_by.call("options")
            t.field "by_unindexed", "Money", &grouping_field_backed_by.call("unindexed")
            t.index "widgets"
          end
        end

        leaf_type_names = metadata.graphql_fields_by_name.transform_values(&:object_grouping_leaf_type_name).compact
        expect(leaf_type_names).to eq({
          "by_color" => "Color",
          "by_name" => "String",
          "by_size" => "Int",
          "by_is_draft" => "Boolean"
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
            resolver: configured_graphql_resolver(:object_with_lookahead)
          ),
          "id" => graphql_field_with(
            name_in_index: "id",
            relation: nil,
            resolver: configured_graphql_resolver(:object_with_lookahead)
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
          "collections" => graphql_field_with(
            name_in_index: "collections_in_index",
            resolver: configured_graphql_resolver(:object_with_lookahead)
          )
        })

        expect(team_collections_sub_aggs.graphql_fields_by_name).to eq({
          "players" => graphql_field_with(
            name_in_index: "the_players",
            resolver: configured_graphql_resolver(:object_with_lookahead)
          )
        })
      end
    end
  end
end
