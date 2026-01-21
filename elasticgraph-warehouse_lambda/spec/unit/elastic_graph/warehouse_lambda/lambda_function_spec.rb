# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/spec_support/lambda_function"

RSpec.describe "Warehouse lambda function" do
  include_context "lambda function", config_overrides_in_yaml: {"warehouse" => {"s3_path_prefix" => "Data001", "s3_bucket_name" => "test-bucket"}}

  it "defines DumpWarehouseData constant" do
    expect_loading_lambda_to_define_constant(
      lambda: "elastic_graph/warehouse_lambda/lambda_function.rb",
      const: :DumpWarehouseData
    ) do |lambda_function|
      expect(lambda_function).to be_a(ElasticGraph::WarehouseLambda::LambdaFunction)
      response = lambda_function.handle_request(event: {"Records" => []}, context: {})
      expect(response).to eq({"batchItemFailures" => []})
      expect(lambda_function.sqs_processor.ignore_sqs_latency_timestamps_from_arns).to eq([].to_set)
    end
  end

  it "configures `ignore_sqs_latency_timestamps_from_arns` based on an ENV var" do
    env_var_value = ::JSON.generate(["ignored-arn1", "ignored-arn2"])

    with_env "IGNORE_SQS_LATENCY_TIMESTAMPS_FROM_ARNS" => env_var_value do
      expect_loading_lambda_to_define_constant(
        lambda: "elastic_graph/warehouse_lambda/lambda_function.rb",
        const: :DumpWarehouseData
      ) do |lambda_function|
        response = lambda_function.handle_request(event: {"Records" => []}, context: {})
        expect(response).to eq({"batchItemFailures" => []})
        expect(lambda_function.sqs_processor.ignore_sqs_latency_timestamps_from_arns).to eq([
          "ignored-arn1",
          "ignored-arn2"
        ].to_set)
      end
    end
  end
end
