# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/spec_support/lambda_function"

RSpec.describe "Indexer lambda function" do
  include_context "lambda function"

  it "processes SQS message payloads" do
    expect_loading_lambda_to_define_constant(
      lambda: "elastic_graph/indexer_lambda/lambda_function.rb",
      const: :ProcessEventStreamEvent
    ) do |lambda_function|
      response = lambda_function.handle_request(event: {"Records" => []}, context: {})
      expect(response).to eq({"batchItemFailures" => []})
    end
  end
end
