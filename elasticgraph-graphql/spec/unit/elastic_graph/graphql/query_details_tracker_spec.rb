# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphql/query_details_tracker"

module ElasticGraph
  class GraphQL
    RSpec.describe QueryDetailsTracker do
      describe ".empty" do
        it "initializes all tracker fields" do
          tracker = QueryDetailsTracker.empty

          expect(tracker.shard_routing_values).to eq ::Set.new
          expect(tracker.search_index_expressions).to eq ::Set.new
          expect(tracker.query_counts_per_datastore_request).to eq []
          expect(tracker.datastore_query_server_duration_ms).to eq 0
          expect(tracker.datastore_query_client_duration_ms).to eq 0
          expect(tracker.queried_shard_count).to eq 0
          expect(tracker.extension_data).to eq({})
          expect(tracker.mutex).to be_a ::Thread::Mutex
        end
      end

      describe "#[]=" do
        let(:tracker) { QueryDetailsTracker.empty }

        it "allows extensions to set custom data in extension_data" do
          tracker["custom_key"] = "custom_value"
          expect(tracker.extension_data).to eq("custom_key" => "custom_value")
        end

        it "allows multiple values to be set" do
          tracker["key1"] = "value1"
          tracker["key2"] = "value2"

          expect(tracker.extension_data).to eq(
            "key1" => "value1",
            "key2" => "value2"
          )
        end

        it "allows overwriting existing extension data" do
          tracker["key"] = "original_value"
          tracker["key"] = "new_value"

          expect(tracker.extension_data).to eq("key" => "new_value")
        end

        it "allows non-string values (per RBS signature)" do
          tracker["int_key"] = 42
          tracker["array_key"] = [1, 2, 3]

          expect(tracker.extension_data).to eq(
            "int_key" => 42,
            "array_key" => [1, 2, 3]
          )
        end
      end
    end
  end
end
