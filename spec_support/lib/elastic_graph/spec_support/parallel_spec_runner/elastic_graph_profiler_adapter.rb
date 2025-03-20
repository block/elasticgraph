# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/spec_support/profiling"

module ElasticGraph
  module ParallelSpecRunner
    module ElasticGraphProfilerAdapter
      def record(...)
        yield # don't waste time recording anything since we silence the reporting below.
      end

      def record_raw(...)
        # don't waste time recording anything since we silence the reporting below.
      end

      # If we're using a parallel test runner we don't want this output to show up at various times as worker
      # processes exit, so we override this to be a no-op.
      def report_results
      end

      ElasticGraphProfiler.singleton_class.prepend(self)
    end
  end
end
