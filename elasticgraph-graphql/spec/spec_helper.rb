# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

# This file is contains RSpec configuration and common support code for `elasticgraph-graphql`.
# Note that it gets loaded by `spec_support/spec_helper.rb` which contains common spec support
# code for all ElasticGraph test suites.

module ElasticGraph
  class GraphQL
    SPEC_ROOT = __dir__
  end
end

RSpec.configure do |config|
  config.define_derived_metadata(absolute_file_path: %r{/elasticgraph-graphql/}) do |meta|
    meta[:builds_graphql] = true
  end

  config.when_first_matching_example_defined(:ensure_no_orphaned_types) { require_relative "support/ensure_no_orphaned_types" }
  config.when_first_matching_example_defined(:query_adapter) { require_relative "support/query_adapter" }
  config.when_first_matching_example_defined(:resolver) { require_relative "support/resolver" }
end

RSpec::Matchers.define :take_less_than do |max_expected_duration|
  require "elastic_graph/support/monotonic_clock"
  clock = ElasticGraph::Support::MonotonicClock.new

  chain(:milliseconds) {}
  supports_block_expectations

  match do |block|
    start = clock.now_in_ms
    block.call
    stop = clock.now_in_ms

    @actual_duration = stop - start
    @actual_duration < max_expected_duration
  end

  failure_message do
    # :nocov: -- only executed when a `take_less_than` expectation fails.
    "expected block to #{description}, but took #{@actual_duration} milliseconds"
    # :nocov:
  end
end
