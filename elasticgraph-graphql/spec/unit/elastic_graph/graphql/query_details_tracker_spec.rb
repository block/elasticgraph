# Copyright 2024 - 2025 Block, Inc.
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
      describe "#set_extension_data" do
        let(:tracker) { QueryDetailsTracker.empty }

        it "allows extensions to set custom data" do
          tracker.set_extension_data("custom_key", "custom_value")
          expect(tracker.extension_data).to eq("custom_key" => "custom_value")
        end

        it "allows multiple extensions to set different data" do
          tracker.set_extension_data("key1", "value1")
          tracker.set_extension_data("key2", "value2")

          expect(tracker.extension_data).to eq(
            "key1" => "value1",
            "key2" => "value2"
          )
        end

        it "allows overwriting existing extension data" do
          tracker.set_extension_data("key", "original_value")
          tracker.set_extension_data("key", "new_value")

          expect(tracker.extension_data).to eq("key" => "new_value")
        end

        it "is thread-safe" do
          threads = []
          100.times do |i|
            threads << Thread.new do
              tracker.set_extension_data("thread_#{i}", "value_#{i}")
            end
          end
          threads.each(&:join)

          expect(tracker.extension_data.size).to eq(100)
          100.times do |i|
            expect(tracker.extension_data["thread_#{i}"]).to eq("value_#{i}")
          end
        end
      end

      describe ".empty" do
        it "initializes with an empty extension_data hash" do
          tracker = QueryDetailsTracker.empty
          expect(tracker.extension_data).to eq({})
        end
      end
    end
  end
end
