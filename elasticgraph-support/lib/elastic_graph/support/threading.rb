# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  module Support
    # @private
    module Threading
      # Like Enumerable#map, but performs the map in parallel using one thread per list item.
      # Exceptions that happen in the threads will propagate to the caller at the end.
      # Due to Ruby's GVL, this will never be helpful for pure computation, but can be
      # quite helpful when dealing with blocking I/O. However, the cost of threads is
      # such that this method should not be used when you have a large list of items to
      # map over (say, hundreds or thousands of items or more).
      def self.parallel_map(items)
        threads = _ = items.map do |item|
          ::Thread.new do
            # Disable reporting of exceptions. We use `value` at the end of this method, which
            # propagates any exception that happened in the thread to the calling thread. If
            # this is true (the default), then the exception is also printed to $stderr which
            # is quite noisy.
            ::Thread.current.report_on_exception = false

            yield item
          end
        end

        # `value` here either returns the value of the final expression in the thread, or raises
        # whatever exception happened in the thread. `join` doesn't propagate the exception in
        # the same way, so we always want to use `Thread#value` even if we are just using threads
        # for side effects.
        threads.map(&:value)
      rescue => e
        e.set_backtrace(e.backtrace + caller)
        raise e
      end
    end
  end
end
