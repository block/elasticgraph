# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/constants"
require "elastic_graph/graphql/aggregation/geo_tile_grouping"
require "support/aggregations_helpers"

module ElasticGraph
  class GraphQL
    module Aggregation
      RSpec.describe GeoTileGrouping do
        include AggregationsHelpers

        describe "#key" do
          it "returns the encoded field path, including the `as_geo_tile` subfield" do
            grouping = geo_tile_grouping_of("foo", "bar", zoom_level: 8)

            expect(grouping.key).to eq "foo.bar.as_geo_tile"
          end

          it "uses GraphQL query field names and aliases when they differ from the name of the field in the index" do
            grouping = geo_tile_grouping_of("foo", "bar", zoom_level: 8, field_names_in_graphql_query: ["oof", "rab", "tile"])

            expect(grouping.key).to eq "oof.rab.tile"
          end
        end

        describe "#encoded_index_field_path" do
          it "returns the encoded field path, excluding the `as_geo_tile` subfield" do
            grouping = geo_tile_grouping_of("foo", "bar", zoom_level: 8)

            expect(grouping.encoded_index_field_path).to eq "foo.bar"
          end

          it "uses the names in the index when they differ from the GraphQL names" do
            grouping = geo_tile_grouping_of("oof", "rab", zoom_level: 8, field_names_in_graphql_query: ["foo", "bar", "tile"])

            expect(grouping.encoded_index_field_path).to eq "oof.rab"
          end

          it "allows a `name_in_index` that references a child field" do
            grouping = geo_tile_grouping_of("foo.c", "bar.d", zoom_level: 8, field_names_in_graphql_query: ["foo", "bar", "tile"])

            expect(grouping.encoded_index_field_path).to eq "foo.c.bar.d"
          end
        end

        describe "#composite_clause" do
          it 'builds a datastore aggregation geo tile grouping clause in the form: {"geotile_grid" => {"field" => field_name, "precision" => zoom_level}}' do
            grouping = geo_tile_grouping_of("foo", "bar", zoom_level: 8)

            expect(grouping.composite_clause).to eq({"geotile_grid" => {
              "field" => "foo.bar",
              "precision" => 8
            }})
          end

          it "merges in the provided grouping options" do
            grouping = geo_tile_grouping_of("foo", "bar", zoom_level: 8)

            clause = grouping.composite_clause(grouping_options: {"optA" => 1, "optB" => false})

            expect(clause["geotile_grid"]).to include({"optA" => 1, "optB" => false})
          end
        end

        describe "#non_composite_clause_for" do
          it "limits the buckets to the requested page size" do
            grouping = geo_tile_grouping_of("foo", "bar", zoom_level: 8)
            query = sub_aggregation_query_of(first: 5)

            clause = grouping.non_composite_clause_for(query)

            expect(clause).to eq({"geotile_grid" => {
              "field" => "foo.bar",
              "precision" => 8,
              "size" => query.paginator.requested_page_size
            }})
          end
        end

        describe "#sort_value" do
          it "orders tile keys in the datastore order: numerically, by `x` and then by `y`" do
            grouping = geo_tile_grouping_of("foo", zoom_level: 8)
            # String order would put "8/215/156" before "8/40/9", and "8/40/10" before "8/40/9".
            ordered_keys = ["8/0/0", "8/0/255", "8/9/0", "8/40/9", "8/40/10", "8/41/0", "8/215/156", "8/255/255"]

            expect(ordered_keys.reverse.sort_by { |key| grouping.sort_value(key) }).to eq ordered_keys
          end

          it "keeps `x` and `y` from overlapping at the max zoom level, where each uses all of its bits" do
            zoom = GEO_TILE_ZOOM_LEVELS.max
            max_coordinate = (1 << zoom) - 1
            grouping = geo_tile_grouping_of("foo", zoom_level: zoom)
            ordered_keys = ["#{zoom}/0/#{max_coordinate}", "#{zoom}/1/0", "#{zoom}/#{max_coordinate}/#{max_coordinate}"]

            expect(ordered_keys.reverse.sort_by { |key| grouping.sort_value(key) }).to eq ordered_keys
          end

          it "returns `nil` for the missing value bucket key" do
            grouping = geo_tile_grouping_of("foo", zoom_level: 8)

            expect(grouping.sort_value(nil)).to be_nil
          end

          # Cursors come from clients, so any JSON value can arrive here.
          ["8/40", "bad", "8/40/99/1", "8/forty/99", "8/-1/99", "30/0/0", "7/40/99", "8/256/99", "8/40/256", 123, false, []].each do |tile_key|
            it "raises a clear error for the invalid cursor value #{tile_key.inspect}" do
              grouping = geo_tile_grouping_of("foo", zoom_level: 8, field_names_in_graphql_query: ["foo", "tile"])

              expect {
                grouping.sort_value(tile_key)
              }.to raise_error(::GraphQL::ExecutionError, "Invalid geo tile cursor value for `foo.tile`.")
            end
          end
        end

        describe "#inner_meta" do
          it "returns inner meta" do
            grouping = geo_tile_grouping_of("foo", zoom_level: 8)

            expect(grouping.inner_meta).to eq({"key_path" => ["key"], "merge_into_bucket" => {}})
          end
        end

        describe "#handles_missing_values?" do
          it "returns false since standalone geo tile aggregations omit documents that have no location" do
            grouping = geo_tile_grouping_of("foo", zoom_level: 8)

            expect(grouping.handles_missing_values?).to be false
          end
        end

        describe "#bounds_count_error_with_value_count?" do
          it "returns true since geo tile aggregations report no count error" do
            grouping = geo_tile_grouping_of("foo", zoom_level: 8)

            expect(grouping.bounds_count_error_with_value_count?).to be true
          end
        end
      end
    end
  end
end
