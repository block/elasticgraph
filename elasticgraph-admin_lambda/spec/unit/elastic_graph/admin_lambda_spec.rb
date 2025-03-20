# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/admin_lambda"
require "elastic_graph/spec_support/lambda_function"

module ElasticGraph
  RSpec.describe AdminLambda do
    describe ".admin_from_env" do
      include_context "lambda function"
      around { |ex| with_lambda_env_vars(&ex) }

      it "builds an admin instance" do
        expect(AdminLambda.admin_from_env).to be_an(Admin)
      end
    end
  end
end
