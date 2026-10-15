# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphql/aggregation/geo_tile_grouping"
require "support/aggregations_helpers"

module ElasticGraph
  class GraphQL
    module Aggregation
      RSpec.describe GeoTileGrouping do
        include AggregationsHelpers

        let(:grouping) do
          GeoTileGrouping.new(field_path: build_field_path(names_in_index: ["position"], names_in_graphql_query: ["location", "tile"]), zoom_level: 8)
        end

        it "uses the index field for the source and query aliases for the bucket key" do
          expect(grouping.key).to eq("location.tile")
          expect(grouping.composite_clause(grouping_options: {"missing_bucket" => true, "order" => "desc"})).to eq({
            "geotile_grid" => {"field" => "position", "precision" => 8, "missing_bucket" => true, "order" => "desc"}
          })
        end

        it "compares tiles in numeric datastore order rather than string order" do
          expect(grouping.sort_value("8/40/99")).to be < grouping.sort_value("8/215/156")
          expect(grouping.sort_value("8/40/9")).to be < grouping.sort_value("8/40/10")
          expect(grouping.sort_value(nil)).to be_nil
        end

        ["8/40", "bad", "8/40/99/1", "8/forty/99", "8/-1/99", "30/0/0", "7/40/99", "8/256/99", "8/40/256", 123, false, []].each do |tile_key|
          it "rejects invalid tile cursor value #{tile_key.inspect}" do
            expect { grouping.sort_value(tile_key) }.to raise_error(::GraphQL::ExecutionError, /Invalid geo tile cursor/)
          end
        end

        it "limits standalone buckets without claiming their counts are exact" do
          expect(grouping.non_composite_clause_for(sub_aggregation_query_of(first: 5))).to eq({"geotile_grid" => {"field" => "position", "precision" => 8, "size" => 6}})
          expect(grouping.handles_missing_values?).to be false
          expect(grouping.inner_meta).to include("count_error_unknown" => true)
        end

        it "uses the full scope count as an upper bound for standalone tile counts" do
          response = {
            "doc_count" => 100,
            grouping.key => {
              "meta" => grouping.inner_meta.merge("grouping_fields" => [grouping.key]),
              "buckets" => [{"key" => "8/40/99", "doc_count" => 15}]
            }
          }
          buckets = NonCompositeGroupingAdapter.prepare_response_buckets(response, [grouping.key], {"size" => 10})
          expect(buckets.first).to include("key" => {grouping.key => "8/40/99"}, "doc_count" => 15, "doc_count_error_upper_bound" => 85)
        end
      end
    end
  end
end
