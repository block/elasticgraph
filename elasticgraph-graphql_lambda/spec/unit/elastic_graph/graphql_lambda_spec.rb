# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphql_lambda"
require "elastic_graph/spec_support/lambda_function"

module ElasticGraph
  RSpec.describe GraphQLLambda do
    describe ".graphql_from_env" do
      include_context "lambda function"
      around { |ex| with_lambda_env_vars(&ex) }

      it "builds a graphql instance" do
        expect(GraphQLLambda.graphql_from_env).to be_a(GraphQL)
      end
    end
  end
end
