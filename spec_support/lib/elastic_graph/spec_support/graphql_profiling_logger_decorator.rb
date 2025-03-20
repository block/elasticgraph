# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "logger"
require "delegate"

module ElasticGraph
  class GraphQLProfilingLoggerDecorator < DelegateClass(::Logger)
    # Profiling is an opt-in thing in our test suite; so here we wrap if profiling is being used.
    def self.maybe_wrap(logger)
      # :nocov: -- on any given test run, only one side of this conditional will be covered
      return logger unless defined?(::ElasticGraphProfiler)
      new(logger)
      # :nocov:
    end

    def info(message)
      if message.is_a?(::Hash) && message["message_type"] == "ElasticGraphQueryExecutorQueryDuration"
        ::ElasticGraphProfiler.record_raw("graphql_duration", message.fetch("duration_ms").to_f / 1000)
        ::ElasticGraphProfiler.record_raw("graphql_datastore_duration", message.fetch("datastore_server_duration_ms").to_f / 1000)
        ::ElasticGraphProfiler.record_raw("graphql_elasticgraph_overhead", message.fetch("elasticgraph_overhead_ms").to_f / 1000)
      end

      super
    end
  end
end
