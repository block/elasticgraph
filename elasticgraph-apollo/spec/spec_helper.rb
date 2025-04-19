# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

# This file is contains RSpec configuration and common support code for `elasticgraph-apollo`.
# Note that it gets loaded by `spec_support/spec_helper.rb` which contains common spec support
# code for all ElasticGraph test suites.

require "graphql"

module ElasticGraph
  # The apollo-federation gem is using a deprecated graphql gem API. It gets this warning:
  #
  # ```
  # `Schema.tracer(ApolloFederation::Tracing::Tracer)` is deprecated; use module-based `trace_with` instead. See: https://graphql-ruby.org/queries/tracing.html
  # apollo-federation-3.10.1/lib/apollo-federation/tracing.rb:12:in 'ApolloFederation::Tracing.use'
  # ```
  #
  # We don't want to see that warning over and over again in our test suite output, so we silence it here.
  # TODO: remove once the warning is fixed in the apollo-federation gem:
  # https://github.com/Gusto/apollo-federation-ruby/issues/277
  module SilenceApolloFederationTracingWarning
    def tracer(new_tracer, silence_deprecation_warning: false)
      super(
        new_tracer,
        silence_deprecation_warning: silence_deprecation_warning || new_tracer == ::ApolloFederation::Tracing::Tracer
      )
    end
  end

  ::GraphQL::Schema.singleton_class.prepend SilenceApolloFederationTracingWarning
end
