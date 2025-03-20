# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/lambda_support/lambda_function"

module ElasticGraph
  module AdminLambda
    # @private
    class LambdaFunction
      prepend LambdaSupport::LambdaFunction

      def initialize
        require "elastic_graph/admin_lambda/rake_adapter"
      end

      def handle_request(event:, context:)
        # @type var event: ::Hash[::String, untyped]
        rake_output = RakeAdapter.run_rake(event.fetch("argv"))

        # Log the output of the rake task. We also want to return it so that when we invoke
        # a lambda rake task from the terminal we can print the output there.
        puts rake_output

        {"rake_output" => rake_output}
      end
    end
  end
end

# Lambda handler for `elasticgraph-admin_lambda`.
HandleAdminRequest = ElasticGraph::AdminLambda::LambdaFunction.new
