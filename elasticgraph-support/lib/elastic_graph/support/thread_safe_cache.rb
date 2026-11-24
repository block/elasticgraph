# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "monitor"

module ElasticGraph
  module Support
    # A lazily populated cache that is safe to share across threads. Use it instead of a `Hash.new { |h, k| h[k] = ... }`
    # cache on long-lived objects: on JRuby, concurrent writes to a plain `Hash` can lose entries.
    #
    # @private
    class ThreadSafeCache
      def initialize
        @values_by_key = {}
        @monitor = ::Monitor.new
      end

      # Returns the cached value for `key`, evaluating the block to compute and cache it on the first call. The block
      # runs while the lock is held. The lock is reentrant, so the block can fetch other keys from the same cache.
      def fetch_or_store(key)
        @monitor.synchronize do
          @values_by_key.fetch(key) { @values_by_key[key] = yield }
        end
      end
    end
  end
end
