# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/spec_support/uses_datastore"

module ElasticGraph
  module ParallelSpecRunner
    # Used to patch `RequestTracker::Request` to remove the index prefix that gets added to our index names when running specs in parallel.
    # Some tests assert on tracked requests and don't expect the index prefix, so it must be removed.
    module RequestTrackerRequestAdapter
      def initialize(http_method:, url:, body:, timeout:)
        super(
          http_method: http_method,
          url: ::URI.parse(url.to_s.gsub(ParallelSpecRunner.index_prefix, "")),
          body: body&.gsub(ParallelSpecRunner.index_prefix, ""),
          timeout: timeout
        )
      end

      RequestTracker::Request.prepend(self)
    end
  end
end
