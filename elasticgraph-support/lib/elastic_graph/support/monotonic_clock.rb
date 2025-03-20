# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  module Support
    # A simple abstraction that provides a monotonic clock.
    #
    # @private
    class MonotonicClock
      # Returns an abstract "now" value in integer milliseconds, suitable for calculating
      # a duration or deadline, without being impacted by leap seconds, etc.
      def now_in_ms
        ::Process.clock_gettime(::Process::CLOCK_MONOTONIC, :millisecond)
      end
    end
  end
end
