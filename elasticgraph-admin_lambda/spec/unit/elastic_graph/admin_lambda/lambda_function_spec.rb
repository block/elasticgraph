# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/spec_support/lambda_function"

RSpec.describe "Admin lambda function" do
  include_context "lambda function"

  it "runs rake" do
    expect_loading_lambda_to_define_constant(
      lambda: "elastic_graph/admin_lambda/lambda_function.rb",
      const: :HandleAdminRequest
    ) do |lambda_function|
      expect {
        response = lambda_function.handle_request(event: {"argv" => ["-T"]}, context: {})
        expect(response["rake_output"]).to include("rake clusters:configure:dry_run")
      }.to output(a_string_including("rake clusters:configure:dry_run")).to_stdout_from_any_process
    end
  end
end
