# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

# During the upgrade of the GraphQL gem from version 2.0.15 to 2.0.16, we discovered that
# some of the schemas generated in our tests were not parseable by the GraphQL gem. Allowing
# invalid GraphQL schemas can hide latent issues (or lead to issues later on when we are forced
# to correct it) so we'd like to prevent invalid schemas from being generated in the first place.
#
# Here we define a method that uses the GraphQL gem to enforce the validity of our generated
# schemas. However, parsing all our test schemas makes our tests 2-3 times slower. We don't
# want to slow down every local test run to add this validation, so it's something that you can
# opt in to via the `VALIDATE_GRAPHQL_SCHEMAS` env var. We also pass this env var from our CI
# build where it's ok if the test suite is slower.
#
# :nocov: -- only one of the two branches gets run on any test run.
return unless ENV["VALIDATE_GRAPHQL_SCHEMAS"]

require "elastic_graph/schema_definition/test_support"
require "graphql"

module ElasticGraph
  module ValidateGraphQLSchemas
    def define_schema_with_schema_elements(...)
      super.tap do |results|
        ValidateGraphQLSchemas.validate_graphql_schema!(results)
      end
    end

    # Hook in to the API tests use to define schemas so that we can automatically validate each schema.
    SchemaDefinition::TestSupport.prepend(self)

    def self.validate_graphql_schema!(results)
      # Allow an example to opt-out of this validation by tagging it with `:dont_validate_graphql_schema`.
      # This can be useful when an example defines an intentionally invalid schema.
      rspec_example_meta = ::RSpec.current_example&.metadata || {}
      return if rspec_example_meta[:dont_validate_graphql_schema]

      ::GraphQL::Schema.from_definition(results.graphql_schema_string)
    rescue ::ElasticGraph::Errors::Error => e
      raise e # re-raise intentional errors raised by ElasticGraph itself.
    rescue => e
      raise(::RuntimeError, <<~EOS, e.backtrace)
        This test generated SDL that can't be parsed by the GraphQL gem. The error[^1] is shown below.
        Note that the extra GraphQL gem parsing validation is not applied by default when you run tests locally.
        The extra validation runs on CI (where we are OK with the slow down that produces), and you can opt into
        it by passing `VALIDATE_GRAPHQL_SCHEMAS=1` when running your tests.

        [^1]: #{e.message}
      EOS
    end
  end
end
# :nocov:
