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
    RSpec.describe "RuntimeMetadata #object_types_by_name--relation metadata" do
      include_context "object type metadata support"

      it "dumps relation metadata from a `relates_to_one` field" do
        metadata = object_type_metadata_for "Widget" do |s|
          s.object_type "Widget" do |t|
            t.field "id", "ID"
            t.relates_to_one "parent", "Widget", via: "parent_id", dir: :out
            t.index "widgets"
          end
        end

        expect(metadata.graphql_fields_by_name.slice("parent")).to eq({
          "parent" => graphql_field_with(
            name_in_index: "parent",
            resolver: configured_graphql_resolver(:nested_relationships),
            relation: SchemaArtifacts::RuntimeMetadata::Relation.new(
              foreign_key: "parent_id",
              direction: :out,
              additional_filter: {},
              foreign_key_nested_paths: []
            )
          )
        })
      end

      it "dumps relation metadata from a `relates_to_many` field" do
        metadata = object_type_metadata_for "Widget" do |s|
          s.object_type "Widget" do |t|
            t.field "id", "ID"
            t.relates_to_many "children", "Widget", via: "parent_id", dir: :in, singular: "child"
            t.index "widgets"
          end
        end

        expected_relation_field = graphql_field_with(
          resolver: configured_graphql_resolver(:nested_relationships),
          relation: SchemaArtifacts::RuntimeMetadata::Relation.new(
            foreign_key: "parent_id",
            direction: :in,
            additional_filter: {},
            foreign_key_nested_paths: []
          )
        )

        expect(metadata.graphql_fields_by_name.slice("children", "child_aggregations")).to eq({
          "children" => expected_relation_field.with(name_in_index: "children"),
          "child_aggregations" => expected_relation_field.with(name_in_index: "child_aggregations")
        })
      end

      it "stores an additional filter on the relation" do
        filter = {"is_enabled" => {"equal_to_any_of" => [true]}}

        metadata = object_type_metadata_for "Widget" do |s|
          s.object_type "Widget" do |t|
            t.field "id", "ID"

            t.relates_to_one "parent", "Widget", via: "parent_id", dir: :in do |r|
              r.additional_filter filter
            end

            t.relates_to_many "children", "Widget", via: "parent_id", dir: :in, singular: "child" do |r|
              r.additional_filter filter
            end

            t.index "widgets"
          end
        end

        expected_relation_field = graphql_field_with(
          resolver: configured_graphql_resolver(:nested_relationships),
          relation: SchemaArtifacts::RuntimeMetadata::Relation.new(
            foreign_key: "parent_id",
            direction: :in,
            additional_filter: filter,
            foreign_key_nested_paths: []
          )
        )

        expect(metadata.graphql_fields_by_name.slice("parent", "children", "child_aggregations")).to eq({
          "children" => expected_relation_field.with(name_in_index: "children"),
          "child_aggregations" => expected_relation_field.with(name_in_index: "child_aggregations"),
          "parent" => expected_relation_field.with(name_in_index: "parent")
        })
      end

      it "converts an additional filter with symbol keys to string keys so it serializes properly" do
        filter = {is_enabled: {equal_to_any_of: [true]}}

        metadata = object_type_metadata_for "Widget" do |s|
          s.object_type "Widget" do |t|
            t.field "id", "ID"

            t.relates_to_one "parent", "Widget", via: "parent_id", dir: :in do |r|
              r.additional_filter filter
            end

            t.relates_to_many "children", "Widget", via: "parent_id", dir: :in, singular: "child" do |r|
              r.additional_filter filter
            end

            t.index "widgets"
          end
        end

        expected_relation_field = graphql_field_with(
          resolver: configured_graphql_resolver(:nested_relationships),
          relation: SchemaArtifacts::RuntimeMetadata::Relation.new(
            foreign_key: "parent_id",
            direction: :in,
            additional_filter: {"is_enabled" => {"equal_to_any_of" => [true]}},
            foreign_key_nested_paths: []
          )
        )

        expect(metadata.graphql_fields_by_name.slice("parent", "children", "child_aggregations")).to eq({
          "children" => expected_relation_field.with(name_in_index: "children"),
          "child_aggregations" => expected_relation_field.with(name_in_index: "child_aggregations"),
          "parent" => expected_relation_field.with(name_in_index: "parent")
        })
      end

      it "merges the filters when `additional_filter` is called multiple times" do
        filter1 = {
          is_enabled: {equal_to_any_of: [true]},
          details: {foo: {lt: 3}}
        }
        filter2 = {
          "details" => {"bar" => {"gt" => 5}},
          "other" => {"lte" => 100}
        }

        metadata = object_type_metadata_for "Widget" do |s|
          s.object_type "Widget" do |t|
            t.field "id", "ID"

            t.relates_to_one "parent", "Widget", via: "parent_id", dir: :in do |r|
              r.additional_filter filter1
              r.additional_filter filter2
            end

            t.relates_to_many "children", "Widget", via: "parent_id", dir: :in, singular: "child" do |r|
              r.additional_filter filter1
              r.additional_filter filter2
            end

            t.index "widgets"
          end
        end

        expected_relation_field = graphql_field_with(
          resolver: configured_graphql_resolver(:nested_relationships),
          relation: SchemaArtifacts::RuntimeMetadata::Relation.new(
            foreign_key: "parent_id",
            direction: :in,
            additional_filter: {
              "is_enabled" => {"equal_to_any_of" => [true]},
              "details" => {"foo" => {"lt" => 3}, "bar" => {"gt" => 5}},
              "other" => {"lte" => 100}
            },
            foreign_key_nested_paths: []
          )
        )

        expect(metadata.graphql_fields_by_name.slice("parent", "children", "child_aggregations")).to eq({
          "children" => expected_relation_field.with(name_in_index: "children"),
          "child_aggregations" => expected_relation_field.with(name_in_index: "child_aggregations"),
          "parent" => expected_relation_field.with(name_in_index: "parent")
        })
      end

      context "when the relation foreign key involves `nested` fields" do
        let(:types_in_dependency_order) do
          [
            "Sponsorship", # references no types
            "Affiliation", # references Sponsorship
            "Player", # references Affiliation
            "Team", # references Player
            "Sponsor" # references Team
          ]
        end

        it "resolves `foreign_key_nested_paths` when types are only referenced after they have been defined" do
          test_foreign_key_nested_paths(types_in_dependency_order)
        end

        it "resolves `foreign_key_nested_paths` when types are referenced before they have been defined" do
          test_foreign_key_nested_paths(types_in_dependency_order.reverse)
        end

        def test_foreign_key_nested_paths(type_definition_order)
          type_defs_by_name = {
            "Affiliation" => lambda do |t|
              t.field "sponsorships", "[Sponsorship!]!" do |f|
                f.mapping type: "nested"
              end
            end,

            "Player" => lambda do |t|
              t.field "name", "String"
              t.field "affiliations", "Affiliation"
            end,

            "Sponsor" => lambda do |t|
              t.field "id", "ID"
              t.field "name", "String"
              t.relates_to_many "affiliated_teams", "Team", via: "players.affiliations.sponsorships.sponsor_id", dir: :in, singular: "affiliated_team"

              t.index "sponsors"
            end,

            "Sponsorship" => lambda do |t|
              t.field "sponsor_id", "ID"
            end,

            "Team" => lambda do |t|
              t.field "id", "ID"
              t.field "players", "[Player!]!" do |f|
                f.mapping type: "nested"
              end

              t.index "teams"
            end
          }

          metadata = object_type_metadata_for "Sponsor" do |s|
            type_definition_order.each do |type|
              s.object_type(type, &type_defs_by_name.fetch(type))
            end
          end

          expected_relation_field = graphql_field_with(
            resolver: configured_graphql_resolver(:nested_relationships),
            relation: SchemaArtifacts::RuntimeMetadata::Relation.new(
              foreign_key: "players.affiliations.sponsorships.sponsor_id",
              direction: :in,
              additional_filter: {},
              foreign_key_nested_paths: ["players", "players.affiliations.sponsorships"]
            )
          )
          expect(metadata.graphql_fields_by_name.slice("affiliated_teams", "affiliated_team_aggregations")).to eq({
            "affiliated_teams" => expected_relation_field.with(name_in_index: "affiliated_teams"),
            "affiliated_team_aggregations" => expected_relation_field.with(name_in_index: "affiliated_team_aggregations")
          })
        end
      end
    end
  end
end
