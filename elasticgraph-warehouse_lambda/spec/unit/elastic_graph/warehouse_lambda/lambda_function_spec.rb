# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/spec_support/lambda_function"

RSpec.describe "Warehouse lambda function" do
  include_context "lambda function", config_overrides_in_yaml: {"warehouse" => {"s3_path_prefix" => "Data001"}}

  # Provide the S3 bucket env var expected by the lambda under test.
  around do |ex|
    with_env({"DATAWAREHOUSE_S3_BUCKET_NAME" => "warehouse-bucket"}) { ex.run }
  end

  it "defines ElasticGraphWarehouse constant" do
    expect_loading_lambda_to_define_constant(
      lambda: "elastic_graph/warehouse_lambda/lambda_function.rb",
      const: :ElasticGraphWarehouse
    ) do |lambda_function|
      expect(lambda_function).to be_a(ElasticGraph::WarehouseLambda::LambdaFunction)
    end
  end

  it "handles empty SQS batch" do
    expect_loading_lambda_to_define_constant(
      lambda: "elastic_graph/warehouse_lambda/lambda_function.rb",
      const: :ElasticGraphWarehouse
    ) do |lambda_function|
      response = lambda_function.handle_request(event: {"Records" => []}, context: {})
      expect(response).to eq({"batchItemFailures" => []})
    end
  end

  it "respects IGNORE_SQS_LATENCY_TIMESTAMPS_FROM_ARNS environment variable" do
    with_env({"IGNORE_SQS_LATENCY_TIMESTAMPS_FROM_ARNS" => '["arn:aws:sqs:us-west-2:123456789:test-queue"]'}) do
      expect_loading_lambda_to_define_constant(
        lambda: "elastic_graph/warehouse_lambda/lambda_function.rb",
        const: :ElasticGraphWarehouse
      ) do |lambda_function|
        response = lambda_function.handle_request(event: {"Records" => []}, context: {})
        expect(response).to eq({"batchItemFailures" => []})
      end
    end
  end

  it "defaults IGNORE_SQS_LATENCY_TIMESTAMPS_FROM_ARNS to empty array when not set" do
    with_env({}) do
      expect_loading_lambda_to_define_constant(
        lambda: "elastic_graph/warehouse_lambda/lambda_function.rb",
        const: :ElasticGraphWarehouse
      ) do |lambda_function|
        response = lambda_function.handle_request(event: {"Records" => []}, context: {})
        expect(response).to eq({"batchItemFailures" => []})
      end
    end
  end
end
