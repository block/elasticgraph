# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/support/thread_safe_cache"

module ElasticGraph
  module Support
    RSpec.describe ThreadSafeCache do
      let(:cache) { ThreadSafeCache.new }

      describe "#fetch_or_store" do
        it "returns the block's value, and returns the cached value on later calls without evaluating the block again" do
          values = %w[first second]

          first = cache.fetch_or_store(:a) { values.shift }
          second = cache.fetch_or_store(:a) { values.shift }

          expect([first, second]).to eq %w[first first]
        end

        it "caches values separately for each key" do
          a = cache.fetch_or_store(:a) { "a value" }
          b = cache.fetch_or_store(:b) { "b value" }

          expect([a, b]).to eq ["a value", "b value"]
        end

        it "caches `nil` and `false` values so that the block is not evaluated again for them" do
          block_calls = []

          2.times do
            cache.fetch_or_store(:nil_key) do
              block_calls << :nil_key
              nil
            end

            cache.fetch_or_store(:false_key) do
              block_calls << :false_key
              false
            end
          end

          expect(block_calls).to eq [:nil_key, :false_key]
        end

        it "allows the block to fetch a different key from the same cache, so that cached values can be built from other cached values" do
          value = cache.fetch_or_store(:outer) do
            "outer wraps #{cache.fetch_or_store(:inner) { "inner" }}"
          end

          expect([value, cache.fetch_or_store(:inner) { "other" }]).to eq ["outer wraps inner", "inner"]
        end

        it "evaluates the block only once when another thread requests the same key while the first thread is evaluating it" do
          block_calls = 0
          entered_block = ::Thread::Queue.new
          release_block = ::Thread::Queue.new
          compute = lambda do
            block_calls += 1
            entered_block << true
            release_block.pop
            "the value"
          end

          first_thread = ::Thread.new { cache.fetch_or_store(:a, &compute) }
          entered_block.pop # Wait until the first thread is inside the block.
          second_thread = ::Thread.new { cache.fetch_or_store(:a, &compute) }
          # The second thread sleeps either waiting for the lock or inside the block (when the cache has no lock).
          ::Thread.pass until second_thread.status == "sleep"
          2.times { release_block << true }

          expect([first_thread.value, second_thread.value]).to eq ["the value", "the value"]
          expect(block_calls).to eq 1
        end
      end
    end
  end
end
