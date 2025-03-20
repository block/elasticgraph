# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "aws-sdk-lambda"
require "aws-sdk-sqs"
require "aws-sdk-cloudwatch"
require "elastic_graph/spec_support/lambda_function"

RSpec.describe "Autoscale indexer lambda function" do
  include_context "lambda function"

  it "autscales the concurrency of the lambda" do
    sqs_client = ::Aws::SQS::Client.new(stub_responses: true).tap do |sqs_client|
      sqs_client.stub_responses(:get_queue_attributes, {
        attributes: {
          "ApproximateNumberOfMessages" => "0",
          "QueueArn" => "arn:aws:sqs:us-west-2:000000000:some-eg-app-queue-name"
        }
      })
    end

    lambda_client = ::Aws::Lambda::Client.new(stub_responses: true)
    cloudwatch_client = ::Aws::CloudWatch::Client.new(stub_responses: true)

    allow(::Aws::SQS::Client).to receive(:new).and_return(sqs_client)
    allow(::Aws::Lambda::Client).to receive(:new).and_return(lambda_client)
    allow(::Aws::CloudWatch::Client).to receive(:new).and_return(cloudwatch_client)

    expect_loading_lambda_to_define_constant(
      lambda: "elastic_graph/indexer_autoscaler_lambda/lambda_function.rb",
      const: :AutoscaleIndexer
    ) do |lambda_function|
      event = {
        "queue_urls" => ["https://sqs.us-west-2.amazonaws.com/000000000/some-eg-app-queue-name"],
        "min_cpu_target" => 70,
        "max_cpu_target" => 80,
        "maximum_concurrency" => 1000,
        "required_free_storage_in_mb" => 100,
        "cluster_name" => "some-eg-cluster",
        "indexer_function_name" => "some-eg-app-indexer"
      }
      lambda_function.handle_request(event: event, context: {})
    end
  end
end
