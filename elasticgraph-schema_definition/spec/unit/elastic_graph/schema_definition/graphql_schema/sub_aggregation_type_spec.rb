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
    RSpec.describe "GraphQL schema generation", "a `*SubAggregation` type" do
      include_context "GraphQL schema spec support"

      shared_examples_for "sub-aggregation types" do
        describe "`*SubAggregation` (singular) types" do
          it "defines one and related relay types for each type referenced from a `nested` field" do
            results = define_schema do |schema|
              schema.object_type "Player" do |t|
                t.field "id", "ID!"
                t.field "name", "String"
              end

              schema.object_type "Team" do |t|
                t.field "id", "ID!"
                t.field "name", "String"
                define_collection_field t, "players", "Player" do |f|
                  f.mapping type: "nested"
                end
                t.index "teams"
              end
            end

            expect(sub_aggregation_type_from(results, "TeamPlayer", include_docs: true)).to eq(<<~EOS.strip)
              """
              Return type representing a bucket of `Player` objects for a sub-aggregation within each `TeamAggregation`.
              """
              type TeamPlayerSubAggregation {
                """
                Details of the count of `Player` documents in a sub-aggregation bucket.
                """
                #{schema_elements.count_detail}: AggregationCountDetail
                """
                Used to specify the `Player` fields to group by. The returned values identify each sub-aggregation bucket.
                """
                #{schema_elements.grouped_by}: PlayerGroupedBy
                """
                Provides computed aggregated values over all `Player` documents in a sub-aggregation bucket.
                """
                #{schema_elements.aggregated_values}: PlayerAggregatedValues
              }
            EOS

            expect(sub_aggregation_connection_type_from(results, "TeamPlayer", include_docs: true)).to eq(<<~EOS.strip)
              """
              Represents a collection of `TeamPlayerSubAggregation` results.
              """
              type TeamPlayerSubAggregationConnection {
                """
                The list of `TeamPlayerSubAggregation` results.
                """
                nodes: [TeamPlayerSubAggregation!]!
              }
            EOS

            # We should not have an Edge type since we don't support pagination at this time.
            expect(sub_aggregation_edge_type_from(results, "TeamPlayer")).to eq(nil)
          end

          it "correctly names them when dealing with a nested-field-in-a-nested-field" do
            results = define_schema do |schema|
              schema.object_type "Season" do |t|
                t.field "year", "Int"
              end

              schema.object_type "Player" do |t|
                t.field "id", "ID!"
                t.field "name", "String"
                define_collection_field t, "seasons", "Season" do |f|
                  f.mapping type: "nested"
                end
              end

              schema.object_type "Team" do |t|
                t.field "id", "ID!"
                t.field "name", "String"
                define_collection_field t, "players", "Player" do |f|
                  f.mapping type: "nested"
                end
                t.index "teams"
              end
            end

            expect(sub_aggregation_type_from(results, "TeamPlayerSeason", include_docs: true)).to eq(<<~EOS.strip)
              """
              Return type representing a bucket of `Season` objects for a sub-aggregation within each `TeamPlayerSubAggregation`.
              """
              type TeamPlayerSeasonSubAggregation {
                """
                Details of the count of `Season` documents in a sub-aggregation bucket.
                """
                #{schema_elements.count_detail}: AggregationCountDetail
                """
                Used to specify the `Season` fields to group by. The returned values identify each sub-aggregation bucket.
                """
                #{schema_elements.grouped_by}: SeasonGroupedBy
                """
                Provides computed aggregated values over all `Season` documents in a sub-aggregation bucket.
                """
                #{schema_elements.aggregated_values}: SeasonAggregatedValues
              }
            EOS

            expect(sub_aggregation_connection_type_from(results, "TeamPlayerSeason", include_docs: true)).to eq(<<~EOS.strip)
              """
              Represents a collection of `TeamPlayerSeasonSubAggregation` results.
              """
              type TeamPlayerSeasonSubAggregationConnection {
                """
                The list of `TeamPlayerSeasonSubAggregation` results.
                """
                nodes: [TeamPlayerSeasonSubAggregation!]!
              }
            EOS

            # We should not have an Edge type since we don't support pagination at this time.
            expect(sub_aggregation_edge_type_from(results, "TeamPlayerSeason")).to eq(nil)
          end

          it "defines separate contextual `*SubAggregation` types for each context a nested type lives in" do
            results = define_schema do |schema|
              schema.object_type "Season" do |t|
                t.field "year", "Int"
                define_collection_field t, "players", "Player" do |f|
                  f.mapping type: "nested"
                end
                define_collection_field t, "comments", "Comment" do |f|
                  f.mapping type: "nested"
                end
              end

              schema.object_type "Player" do |t|
                t.field "id", "ID!"
                t.field "name", "String"
                define_collection_field t, "comments", "Comment" do |f|
                  f.mapping type: "nested"
                end
              end

              schema.object_type "Comment" do |t|
                t.field "author", "String"
                t.field "text", "String"
              end

              schema.object_type "Team" do |t|
                t.field "id", "ID!"
                t.field "name", "String"
                define_collection_field t, "current_players", "Player" do |f|
                  f.mapping type: "nested"
                end

                define_collection_field t, "seasons", "Season" do |f|
                  f.mapping type: "nested"
                end
                t.index "teams"
              end
            end

            expect(sub_aggregation_type_from(results, "TeamPlayer").split("\n").first).to eq("type TeamPlayerSubAggregation {")
            expect(sub_aggregation_type_from(results, "TeamSeasonPlayer").split("\n").first).to eq("type TeamSeasonPlayerSubAggregation {")
            expect(sub_aggregation_type_from(results, "TeamPlayerComment").split("\n").first).to eq("type TeamPlayerCommentSubAggregation {")
            expect(sub_aggregation_type_from(results, "TeamSeasonPlayerComment").split("\n").first).to eq("type TeamSeasonPlayerCommentSubAggregation {")
            expect(sub_aggregation_type_from(results, "TeamSeasonConnectionPlayer")).to be nil
            expect(sub_aggregation_type_from(results, "TeamSeasonConnectionComment")).to be nil
            expect(sub_aggregation_type_from(results, "TeamSeasonConnectionPlayerComment")).to be nil
            expect(sub_aggregation_type_from(results, "TeamSeasonConnectionPlayerConnectionComment")).to be nil
            expect(sub_aggregation_type_from(results, "TeamPlayerConnectionComment")).to be nil
          end

          it "defines one and related relay types when there are extra non-nested object layers in the definition" do
            results = define_schema do |schema|
              schema.object_type "Player" do |t|
                t.field "id", "ID!"
                t.field "name", "String"
              end

              schema.object_type "TeamPayroll" do |t|
                t.field "personnel", "TeamPersonnel"
              end

              schema.object_type "TeamPersonnel" do |t|
                define_collection_field t, "players", "Player" do |f|
                  f.mapping type: "nested"
                end
              end

              schema.object_type "Team" do |t|
                t.field "id", "ID!"
                t.field "name", "String"
                t.field "payroll", "TeamPayroll"
                t.index "teams"
              end
            end

            expect(sub_aggregation_type_from(results, "TeamPlayer", include_docs: true)).to eq(<<~EOS.strip)
              """
              Return type representing a bucket of `Player` objects for a sub-aggregation within each `TeamAggregation`.
              """
              type TeamPlayerSubAggregation {
                """
                Details of the count of `Player` documents in a sub-aggregation bucket.
                """
                #{schema_elements.count_detail}: AggregationCountDetail
                """
                Used to specify the `Player` fields to group by. The returned values identify each sub-aggregation bucket.
                """
                #{schema_elements.grouped_by}: PlayerGroupedBy
                """
                Provides computed aggregated values over all `Player` documents in a sub-aggregation bucket.
                """
                #{schema_elements.aggregated_values}: PlayerAggregatedValues
              }
            EOS

            expect(sub_aggregation_connection_type_from(results, "TeamPlayer", include_docs: true)).to eq(<<~EOS.strip)
              """
              Represents a collection of `TeamPlayerSubAggregation` results.
              """
              type TeamPlayerSubAggregationConnection {
                """
                The list of `TeamPlayerSubAggregation` results.
                """
                nodes: [TeamPlayerSubAggregation!]!
              }
            EOS

            # We should not have an Edge type since we don't support pagination at this time.
            expect(sub_aggregation_edge_type_from(results, "TeamPlayer")).to eq(nil)
          end

          it "does not define one or related relay types for types which are not referenced from a `nested` field" do
            results = define_schema do |schema|
              schema.object_type "Player" do |t|
                t.field "id", "ID!"
                t.field "name", "String"
              end

              schema.object_type "Team" do |t|
                t.field "id", "ID!"
                define_collection_field t, "players", "Player" do |f|
                  f.mapping type: "object"
                end
                t.index "teams"
              end
            end

            expect(sub_aggregation_type_from(results, "Player")).to eq nil
            expect(sub_aggregation_connection_type_from(results, "Player")).to eq(nil)
            expect(sub_aggregation_edge_type_from(results, "Player")).to eq(nil)
          end

          it "omits the `grouped_by` field if no fields are groupable" do
            results = define_schema do |schema|
              schema.object_type "Player" do |t|
                t.field "id", "ID!", groupable: false
                t.field "name", "String", groupable: false
              end

              schema.object_type "Team" do |t|
                t.field "id", "ID!"
                t.field "name", "String"
                define_collection_field t, "players", "Player" do |f|
                  f.mapping type: "nested"
                end
                t.index "teams"
              end
            end

            expect(sub_aggregation_type_from(results, "TeamPlayer")).to eq(<<~EOS.strip)
              type TeamPlayerSubAggregation {
                #{schema_elements.count_detail}: AggregationCountDetail
                #{schema_elements.aggregated_values}: PlayerAggregatedValues
              }
            EOS
          end

          it "omits the `aggregated_values` field if no fields are aggregatable" do
            results = define_schema do |schema|
              schema.object_type "Player" do |t|
                t.field "id", "ID!", aggregatable: false
                t.field "name", "String", aggregatable: false
              end

              schema.object_type "Team" do |t|
                t.field "id", "ID!"
                t.field "name", "String"
                define_collection_field t, "players", "Player" do |f|
                  f.mapping type: "nested"
                end
                t.index "teams"
              end
            end

            expect(sub_aggregation_type_from(results, "TeamPlayer")).to eq(<<~EOS.strip)
              type TeamPlayerSubAggregation {
                #{schema_elements.count_detail}: AggregationCountDetail
                #{schema_elements.grouped_by}: PlayerGroupedBy
              }
            EOS
          end
        end

        describe "`*SubAggregations` (plural) types" do
          it "defines one with a field for each `nested` field of the source type" do
            results = define_schema do |schema|
              schema.object_type "Player" do |t|
                t.field "name", "String"
              end

              schema.object_type "Season" do |t|
                t.field "year", "Int"
              end

              schema.object_type "Team" do |t|
                t.field "id", "ID!"
                t.field "name", "String"
                define_collection_field t, "players_nested", "Player" do |f|
                  f.documentation "The players on the team."
                  f.mapping type: "nested"
                end
                define_collection_field t, "seasons_nested", "Season" do |f|
                  f.documentation "The seasons the team has played."
                  f.mapping type: "nested"
                end
                define_collection_field t, "players_object", "Player" do |f|
                  f.mapping type: "object"
                end
                define_collection_field t, "seasons_object", "Season" do |f|
                  f.mapping type: "object"
                end
                t.index "teams"
              end
            end

            expect(aggregation_sub_aggregations_type_from(results, "Team", include_docs: true)).to eq(<<~EOS.strip)
              """
              Provides access to the `#{schema_elements.sub_aggregations}` within each `TeamAggregation`.
              """
              type TeamAggregationSubAggregations {
                """
                Used to perform a sub-aggregation of `players_nested`:

                > The players on the team.
                """
                players_nested(
                  """
                  Used to filter the `Player` documents included in this sub-aggregation based on the provided criteria.
                  """
                  #{schema_elements.filter}: PlayerFilterInput
                  """
                  Determines how many sub-aggregation buckets should be returned.
                  """
                  #{schema_elements.first}: Int): TeamPlayerSubAggregationConnection
                """
                Used to perform a sub-aggregation of `seasons_nested`:

                > The seasons the team has played.
                """
                seasons_nested(
                  """
                  Used to filter the `Season` documents included in this sub-aggregation based on the provided criteria.
                  """
                  #{schema_elements.filter}: SeasonFilterInput
                  """
                  Determines how many sub-aggregation buckets should be returned.
                  """
                  #{schema_elements.first}: Int): TeamSeasonSubAggregationConnection
              }
            EOS
          end

          it "allows the sub-aggregation fields to be customized" do
            results = define_schema do |schema|
              schema.raw_sdl "directive @external on FIELD_DEFINITION"

              schema.object_type "Player" do |t|
                t.field "name", "String"
              end

              schema.object_type "Season" do |t|
                t.field "year", "Int"
              end

              schema.object_type "Team" do |t|
                t.field "id", "ID!"
                t.field "name", "String"

                define_collection_field t, "players_nested", "Player" do |f|
                  f.mapping type: "nested"
                  f.customize_sub_aggregations_field do |saf|
                    saf.directive "deprecated"
                  end
                end

                define_collection_field t, "seasons_nested", "Season" do |f|
                  f.mapping type: "nested"
                  f.customize_sub_aggregations_field do |saf|
                    saf.directive "external"
                  end
                end

                t.index "teams"
              end
            end

            expect(aggregation_sub_aggregations_type_from(results, "Team")).to eq(<<~EOS.strip)
              type TeamAggregationSubAggregations {
                players_nested(
                  #{schema_elements.filter}: PlayerFilterInput
                  #{schema_elements.first}: Int): TeamPlayerSubAggregationConnection @deprecated
                seasons_nested(
                  #{schema_elements.filter}: SeasonFilterInput
                  #{schema_elements.first}: Int): TeamSeasonSubAggregationConnection @external
              }
            EOS
          end

          it "defines extra types and fields when there is an additional object layer in the definition" do
            results = define_schema do |schema|
              schema.object_type "Player" do |t|
                t.field "name", "String"
              end

              schema.object_type "Season" do |t|
                t.field "year", "Int"
              end

              schema.object_type "TeamCollections" do |t|
                define_collection_field t, "players_nested", "Player" do |f|
                  f.mapping type: "nested"
                end
                define_collection_field t, "seasons_nested", "Season" do |f|
                  f.mapping type: "nested"
                end
                define_collection_field t, "players_object", "Player" do |f|
                  f.mapping type: "object"
                end
                define_collection_field t, "seasons_object", "Season" do |f|
                  f.mapping type: "object"
                end
              end

              schema.object_type "Team" do |t|
                t.field "id", "ID!"
                t.field "name", "String"
                t.field "collections", "TeamCollections"
                t.index "teams"
              end
            end

            expect(aggregation_sub_aggregations_type_from(results, "Team", include_docs: true)).to eq(<<~EOS.strip)
              """
              Provides access to the `#{schema_elements.sub_aggregations}` within each `TeamAggregation`.
              """
              type TeamAggregationSubAggregations {
                """
                Used to perform a sub-aggregation of `collections`.
                """
                collections: TeamAggregationCollectionsSubAggregations
              }
            EOS

            expect(aggregation_sub_aggregations_type_from(results, "Team", under: "Collections", include_docs: true)).to eq(<<~EOS.strip)
              """
              Provides access to the `#{schema_elements.sub_aggregations}` under `collections` within each `TeamAggregation`.
              """
              type TeamAggregationCollectionsSubAggregations {
                """
                Used to perform a sub-aggregation of `players_nested`.
                """
                players_nested(
                  """
                  Used to filter the `Player` documents included in this sub-aggregation based on the provided criteria.
                  """
                  #{schema_elements.filter}: PlayerFilterInput
                  """
                  Determines how many sub-aggregation buckets should be returned.
                  """
                  #{schema_elements.first}: Int): TeamPlayerSubAggregationConnection
                """
                Used to perform a sub-aggregation of `seasons_nested`.
                """
                seasons_nested(
                  """
                  Used to filter the `Season` documents included in this sub-aggregation based on the provided criteria.
                  """
                  #{schema_elements.filter}: SeasonFilterInput
                  """
                  Determines how many sub-aggregation buckets should be returned.
                  """
                  #{schema_elements.first}: Int): TeamSeasonSubAggregationConnection
              }
            EOS
          end

          it "defines extra types and fields when there are multiple additional object layers in the definition" do
            results = define_schema do |schema|
              schema.object_type "Player" do |t|
                t.field "name", "String"
              end

              schema.object_type "Season" do |t|
                t.field "year", "Int"
              end

              schema.object_type "TeamCollectionsInner" do |t|
                define_collection_field t, "players_nested", "Player" do |f|
                  f.mapping type: "nested"
                end
                define_collection_field t, "seasons_nested", "Season" do |f|
                  f.mapping type: "nested"
                end
                define_collection_field t, "players_object", "Player" do |f|
                  f.mapping type: "object"
                end
                define_collection_field t, "seasons_object", "Season" do |f|
                  f.mapping type: "object"
                end
              end

              schema.object_type "TeamCollectionsOuter" do |t|
                t.field "inner", "TeamCollectionsInner"
              end

              schema.object_type "Team" do |t|
                t.field "id", "ID!"
                t.field "name", "String"
                t.field "outer_collections", "TeamCollectionsOuter"
                t.index "teams"
              end
            end

            expect(aggregation_sub_aggregations_type_from(results, "Team", include_docs: true)).to eq(<<~EOS.strip)
              """
              Provides access to the `#{schema_elements.sub_aggregations}` within each `TeamAggregation`.
              """
              type TeamAggregationSubAggregations {
                """
                Used to perform a sub-aggregation of `outer_collections`.
                """
                outer_collections: TeamAggregationOuterCollectionsSubAggregations
              }
            EOS

            expect(aggregation_sub_aggregations_type_from(results, "Team", under: "OuterCollections", include_docs: true)).to eq(<<~EOS.strip)
              """
              Provides access to the `#{schema_elements.sub_aggregations}` under `outer_collections` within each `TeamAggregation`.
              """
              type TeamAggregationOuterCollectionsSubAggregations {
                """
                Used to perform a sub-aggregation of `inner`.
                """
                inner: TeamAggregationOuterCollectionsInnerSubAggregations
              }
            EOS

            expect(aggregation_sub_aggregations_type_from(results, "Team", under: "OuterCollectionsInner", include_docs: true)).to eq(<<~EOS.strip)
              """
              Provides access to the `#{schema_elements.sub_aggregations}` under `outer_collections.inner` within each `TeamAggregation`.
              """
              type TeamAggregationOuterCollectionsInnerSubAggregations {
                """
                Used to perform a sub-aggregation of `players_nested`.
                """
                players_nested(
                  """
                  Used to filter the `Player` documents included in this sub-aggregation based on the provided criteria.
                  """
                  #{schema_elements.filter}: PlayerFilterInput
                  """
                  Determines how many sub-aggregation buckets should be returned.
                  """
                  #{schema_elements.first}: Int): TeamPlayerSubAggregationConnection
                """
                Used to perform a sub-aggregation of `seasons_nested`.
                """
                seasons_nested(
                  """
                  Used to filter the `Season` documents included in this sub-aggregation based on the provided criteria.
                  """
                  #{schema_elements.filter}: SeasonFilterInput
                  """
                  Determines how many sub-aggregation buckets should be returned.
                  """
                  #{schema_elements.first}: Int): TeamSeasonSubAggregationConnection
              }
            EOS
          end

          it "generates the expected types when dealing with a nested-field-in-a-nested-field" do
            results = define_schema do |schema|
              schema.object_type "Season" do |t|
                t.field "year", "Int"
              end

              schema.object_type "Player" do |t|
                t.field "id", "ID!"
                t.field "name", "String"
                define_collection_field t, "seasons", "Season" do |f|
                  f.mapping type: "nested"
                end
              end

              schema.object_type "Team" do |t|
                t.field "id", "ID!"
                t.field "name", "String"
                define_collection_field t, "players", "Player" do |f|
                  f.mapping type: "nested"
                end
                t.index "teams"
              end
            end

            expect(aggregation_sub_aggregations_type_from(results, "Team", include_docs: true)).to eq(<<~EOS.strip)
              """
              Provides access to the `#{schema_elements.sub_aggregations}` within each `TeamAggregation`.
              """
              type TeamAggregationSubAggregations {
                """
                Used to perform a sub-aggregation of `players`.
                """
                players(
                  """
                  Used to filter the `Player` documents included in this sub-aggregation based on the provided criteria.
                  """
                  #{schema_elements.filter}: PlayerFilterInput
                  """
                  Determines how many sub-aggregation buckets should be returned.
                  """
                  #{schema_elements.first}: Int): TeamPlayerSubAggregationConnection
              }
            EOS

            expect(sub_aggregation_type_from(results, "TeamPlayer", include_docs: true)).to eq(<<~EOS.strip)
              """
              Return type representing a bucket of `Player` objects for a sub-aggregation within each `TeamAggregation`.
              """
              type TeamPlayerSubAggregation {
                """
                Details of the count of `Player` documents in a sub-aggregation bucket.
                """
                #{schema_elements.count_detail}: AggregationCountDetail
                """
                Used to specify the `Player` fields to group by. The returned values identify each sub-aggregation bucket.
                """
                #{schema_elements.grouped_by}: PlayerGroupedBy
                """
                Provides computed aggregated values over all `Player` documents in a sub-aggregation bucket.
                """
                #{schema_elements.aggregated_values}: PlayerAggregatedValues
                """
                Used to perform sub-aggregations of `TeamPlayerSubAggregation` data.
                """
                #{schema_elements.sub_aggregations}: TeamPlayerSubAggregationSubAggregations
              }
            EOS

            expect(sub_aggregation_sub_aggregations_type_from(results, "TeamPlayer", include_docs: true)).to eq(<<~EOS.strip)
              """
              Provides access to the `#{schema_elements.sub_aggregations}` within each `TeamPlayerSubAggregation`.
              """
              type TeamPlayerSubAggregationSubAggregations {
                """
                Used to perform a sub-aggregation of `seasons`.
                """
                seasons(
                  """
                  Used to filter the `Season` documents included in this sub-aggregation based on the provided criteria.
                  """
                  #{schema_elements.filter}: SeasonFilterInput
                  """
                  Determines how many sub-aggregation buckets should be returned.
                  """
                  #{schema_elements.first}: Int): TeamPlayerSeasonSubAggregationConnection
              }
            EOS
          end

          it "supports aggregations for a type that's both a root indexed type and embedded, when we have object and nested fields" do
            results = define_schema do |schema|
              schema.object_type "Team" do |t|
                t.field "id", "ID!"
                t.field "name", "String"

                define_collection_field t, "current_players", "Player" do |f|
                  f.mapping type: "object"
                end

                t.index "teams"
              end

              schema.object_type "Player" do |t|
                t.field "id", "ID"
                t.field "name", "String"

                define_collection_field t, "seasons", "Season" do |f|
                  f.mapping type: "nested"
                end

                t.index "players"
              end

              schema.object_type "Season" do |t|
                t.field "year", "Int"
              end
            end

            expect(aggregation_sub_aggregations_type_from(results, "Team")).to eq(<<~EOS.strip)
              type TeamAggregationSubAggregations {
                current_players: TeamAggregationCurrentPlayersSubAggregations
              }
            EOS

            expect(aggregation_sub_aggregations_type_from(results, "Team", under: "CurrentPlayers")).to eq(<<~EOS.strip)
              type TeamAggregationCurrentPlayersSubAggregations {
                seasons(
                  #{schema_elements.filter}: SeasonFilterInput
                  #{schema_elements.first}: Int): TeamSeasonSubAggregationConnection
              }
            EOS

            expect(aggregation_sub_aggregations_type_from(results, "Player")).to eq(<<~EOS.strip)
              type PlayerAggregationSubAggregations {
                seasons(
                  #{schema_elements.filter}: SeasonFilterInput
                  #{schema_elements.first}: Int): PlayerSeasonSubAggregationConnection
              }
            EOS
          end

          it "does not define any for an indexed type that has no nested fields" do
            results = define_schema do |schema|
              schema.object_type "Team" do |t|
                t.field "id", "ID!"
                t.field "name", "String"
                t.index "teams"
              end
            end

            expect(aggregation_sub_aggregations_type_from(results, "Team")).to eq nil
          end

          it "does not get stuck in infinite recursion when a nested field is referenced from a type in a circular relationship with another type" do
            results = define_schema do |schema|
              schema.object_type "Component" do |t|
                t.field "id", "ID!"
                t.relates_to_one "widget", "Widget", via: "widgetId", dir: :out
                t.index "components"
              end

              schema.object_type "Widget" do |t|
                t.field "id", "ID!"
                t.relates_to_one "part", "Part", via: "partId", dir: :out
                t.relates_to_one "component", "Component", via: "widgetId", dir: :out
                t.index "widgets"
              end

              schema.object_type "Material" do |t|
                t.field "type", "String"
              end

              schema.object_type "Part" do |t|
                t.field "id", "ID!"
                define_collection_field t, "materials", "Material" do |f|
                  f.mapping type: "nested"
                end
                t.index "parts"
              end
            end

            expect(aggregation_sub_aggregations_type_from(results, "Part")).to eq <<~EOS.strip
              type PartAggregationSubAggregations {
                materials(
                  #{schema_elements.filter}: MaterialFilterInput
                  #{schema_elements.first}: Int): PartMaterialSubAggregationConnection
              }
            EOS
          end
        end

        it "avoids generating sub-aggregation types for type unions that have indexed sub-types because it is hard to do correctly and we do not need it yet" do
          results = define_schema do |schema|
            schema.object_type "Options" do |t|
              t.field "color", "String"
            end

            schema.object_type "Widget" do |t|
              t.field "id", "ID"
              t.field "nested_options", "[Options!]!" do |f|
                # This mapping field is what triggers sub-aggregation types to be generated at all.
                f.mapping type: "nested"
              end
              t.index "widgets"
            end

            schema.object_type "Component" do |t|
              t.field "id", "ID"
              t.index "components"
            end

            schema.union_type "WidgetOrComponent" do |t|
              t.subtypes "Widget", "Component"
            end
          end

          # They should be generated for `Widget`...
          expect(results.lines.grep(/WidgetOptions\w*SubAgg/)).not_to be_empty
          # ...but not for `WidgetOrComponent`.
          expect(results.lines.grep(/WidgetOrComponentOptions\w*SubAgg/)).to be_empty

          # And its aggregation type should not have a `sub_aggregations` field.
          expect(aggregation_type_from(results, "WidgetOrComponent")).to eq(<<~EOS.strip)
            type WidgetOrComponentAggregation {
              #{schema_elements.count}: JsonSafeLong!
              #{schema_elements.aggregated_values}: WidgetOrComponentAggregatedValues
            }
          EOS
        end
      end

      with_both_casing_forms do
        context "when collection fields are defined as a GraphQL list" do
          include_examples "sub-aggregation types"

          def define_collection_field(parent_type, field_name, element_type_name, &block)
            parent_type.field(field_name, "[#{element_type_name}!]!", &block)
          end
        end

        context "when collection fields are defined as a relay connection using `paginated_connection_field`" do
          include_examples "sub-aggregation types"

          def define_collection_field(parent_type, field_name, element_type_name, &block)
            parent_type.paginated_collection_field(field_name, element_type_name, &block)
          end
        end
      end
    end
  end
end
