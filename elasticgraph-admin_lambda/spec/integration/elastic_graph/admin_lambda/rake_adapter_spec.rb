# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/admin_lambda/rake_adapter"
require "elastic_graph/spec_support/lambda_function"

module ElasticGraph
  module AdminLambda
    RSpec.describe RakeAdapter do
      include_context "lambda function"

      around do |ex|
        # Ensure the `record_task_metadata` flag is restored to its original value after running the test.
        # It impacts how rake task descriptions are processed inside rake, and `rake -T` causes the value
        # to change. We have other tests in this repository that will fail if we allow this to leak this
        # state change and if they run after this one.
        orig = ::Rake::TaskManager.record_task_metadata
        ex.run
        ::Rake::TaskManager.record_task_metadata = orig
      end

      it "runs the provided `argv` against our desired Rakefile, returning the printed output" do
        with_lambda_env_vars do
          output = RakeAdapter.run_rake(["-T"])

          expect(rake_tasks_printed_to(output)).to include(
            "clusters:configure:perform",
            "indices:drop_prototypes"
          ).and exclude(
            # The `lambda:*` and `terraform:*` rake tasks are defined by elasticgraph-lambda only for
            # local usage, and are not intended to be available to be run from the `admin` lambda.
            a_string_starting_with("lambda:"),
            a_string_starting_with("terraform:"),
            # The `schema_artifacts:*` task are only intended for local usage, and should not be available in the lambda context.
            a_string_starting_with("schema_artifacts:")
          )
        end
      end

      def rake_tasks_printed_to(string)
        string
          .split("\n")
          .map { |line| line[/^rake (\S+)/, 1] }
          .compact
      end
    end
  end
end
