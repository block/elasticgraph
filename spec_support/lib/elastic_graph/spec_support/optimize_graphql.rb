# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

# Our test suite does _a ton_ of GraphQL parsing, given that `ElasticGraph::GraphQL`
# is instantated from scratch in virtually every `elasticgraph-graphql` test, and the GraphQL schema gets re-parsed
# each time. Using `profiling.rb` we've found that GraphQL parsing takes up a significant portion
# of our test suite runtime. Here we optimize it by simply memoizing the results of parsing a
# GraphQL string (which applies to both schema definitions and GraphQL queries). The GraphQL
# gem provides a nice `GraphQL.default_parser` API we can use to plug in our own parser, which just
# wraps the built-in one with memoization.
#
# As of 2021-12-29, on a local macbook, without this optimization, `script/run_all_specs` reports:
#
# > ========================================================================================================================
# > Top 10 profiling results:
# > 1) `ElasticGraph::GraphQL::Schema#initialize`: 362 calls in 24.026 sec (0.066 sec avg)
# > Max time: 0.231 sec for `./elasticgraph/spec/acceptance/application_spec.rb[1:2:2]` from `./spec/acceptance/application_spec.rb:18:in `block in call_graphql_query'`
# > ------------------------------------------------------------------------------------------------------------------------
# > 2) `Class#from_definition`: 370 calls in 23.064 sec (0.062 sec avg)
# > Max time: 0.212 sec for `./elasticgraph/spec/acceptance/application_spec.rb[1:2:2]` from `./spec/acceptance/application_spec.rb:18:in `block in call_graphql_query'`
# > ========================================================================================================================
# >
# > Finished in 1 minute 1.6 seconds (files took 3.76 seconds to load)
# > 1859 examples, 0 failures
# > script/run_all_specs  53.84s user 5.59s system 89% cpu 1:06.58 total
#
# With this optimization in place, it reports:
#
# > ========================================================================================================================
# > Top 10 profiling results:
# > 1) `ElasticGraph::GraphQL::Schema#initialize`: 362 calls in 10.688 sec (0.03 sec avg)
# > Max time: 0.192 sec for `./elasticgraph/spec/acceptance/application_spec.rb[1:1:5]` from `./spec/acceptance/application_spec.rb:18:in `block in call_graphql_query'`
# > ------------------------------------------------------------------------------------------------------------------------
# > 2) `Class#from_definition`: 370 calls in 9.297 sec (0.025 sec avg)
# > Max time: 0.175 sec for `./elasticgraph/spec/acceptance/application_spec.rb[1:1:5]` from `./spec/acceptance/application_spec.rb:18:in `block in call_graphql_query'`
# > ========================================================================================================================
# >
# > Finished in 47.41 seconds (files took 3.69 seconds to load)
# > 1859 examples, 0 failures
# > script/run_all_specs  39.91s user 5.65s system 87% cpu 52.142 total
#
# The difference is even starker when simplecov is loaded (as it is when you run `script/quick_build`). Without this:
#
# > ========================================================================================================================
# > Top 10 profiling results:
# > 1) `ElasticGraph::GraphQL::Schema#initialize`: 362 calls in 58.334 sec (0.161 sec avg)
# > Max time: 0.453 sec for `./elasticgraph/spec/acceptance/application_spec.rb[1:1:9:5]` from `./spec/acceptance/application_spec.rb:18:in `block in call_graphql_query'`
# > ------------------------------------------------------------------------------------------------------------------------
# > 2) `Class#from_definition`: 370 calls in 57.868 sec (0.156 sec avg)
# > Max time: 0.438 sec for `./elasticgraph/spec/acceptance/application_spec.rb[1:1:9:5]` from `./spec/acceptance/application_spec.rb:18:in `block in call_graphql_query'`
# > ========================================================================================================================
# >
# > Finished in 1 minute 38.8 seconds (files took 4 seconds to load)
# > 1859 examples, 0 failures
# > COVERAGE=1 script/run_all_specs 91.88s user 5.96s system 92% cpu 1:45.30 total
#
# With this:

# > ========================================================================================================================
# > Top 10 profiling results:
# > 1) `ElasticGraph::GraphQL::Schema#initialize`: 362 calls in 16.538 sec (0.046 sec avg)
# > Max time: 0.348 sec for `./elasticgraph/spec/acceptance/application_spec.rb[1:2:5]` from `./spec/acceptance/application_spec.rb:18:in `block in call_graphql_query'`
# > ------------------------------------------------------------------------------------------------------------------------
# > 2) `Class#from_definition`: 370 calls in 15.263 sec (0.041 sec avg)
# > Max time: 0.376 sec for `./elasticgraph/spec/unit/elastic_graph/application_spec.rb[1:9:1]` from `./spec/unit/elastic_graph/application_spec.rb:136:in `block (3 levels) in <module:ElasticGraph>'`
# > ========================================================================================================================
# >
# > Finished in 55.28 seconds (files took 3.76 seconds to load)
# > 1859 examples, 0 failures
# > COVERAGE=1 script/run_all_specs 49.01s user 5.63s system 89% cpu 1:01.17 total
#
# That's a 40% reduction in test suite runtime when simplecov is enabled, and a 20% reduction
# when simplecov is not enabled.

# Guard against this file applying in a CI build since it makes our tests slightly
# less accurate (production doesn't have this kind of memoization).
# :nocov: -- only one branch is covered on any given run
abort "#{__FILE__} should not be loaded in a CI environment but was" if ENV["CI"]
# :nocov:

module ElasticGraph
  class MemoizingGraphQLParser
    # :nocov: some of the gem test suites don't trigger calls to these methods.
    def self.parse(graphql_string, filename: nil, trace: ::GraphQL::Tracing::NullTrace, max_tokens: nil)
      memoized_results[graphql_string] ||= ::GraphQL::Language::Parser.parse(
        graphql_string,
        filename: filename,
        trace: trace,
        max_tokens: max_tokens
      )
    end

    def self.memoized_results
      @memoized_results ||= {}
    end
    # :nocov:
  end
end

# To use our parser, we need to set `GraphQL.default_parser`. However, we do not want to
# `require "graphql"` here. That would slow down test runs for individual unit tests that
# don't involve GraphQL at all (of which there are many!). Instead, we want to reactively
# set `default_parser` as soon as the `GraphQL` module is defined. To do that, we use the
# tracepoint API (from the Ruby standard library) and set it as soon as the `GraphQL` module
# has been defined.
trace = TracePoint.new(:end) do |tp|
  # :nocov: -- for some reason simplecov reports these lines as uncovered (but they do get run). Maybe the tracepoint API interferes?
  if tp.path.end_with?("graphql.rb") && tp.self.name == "GraphQL"
    trace.disable # once we've set the default parser we don't want this trace running anymore.
    ::GraphQL.default_parser = ElasticGraph::MemoizingGraphQLParser
  end
  # :nocov:
end

trace.enable
