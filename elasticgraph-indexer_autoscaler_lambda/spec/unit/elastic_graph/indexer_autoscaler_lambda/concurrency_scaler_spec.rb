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
require "elastic_graph/indexer_autoscaler_lambda/concurrency_scaler"
require "support/builds_indexer_autoscaler"

module ElasticGraph
  class IndexerAutoscalerLambda
    RSpec.describe ConcurrencyScaler, :capture_logs do
      include BuildsIndexerAutoscalerLambda

      describe "#tune_indexer_concurrency" do
        let(:indexer_function_name) { "indexer-lambda" }
        let(:min_cpu_target) { 70 }
        let(:max_cpu_target) { 80 }
        let(:cpu_midpoint) { 75 }
        let(:maximum_concurrency) { 1000 }
        let(:required_free_storage_in_mb) { 10000 }

        it "1.5x the concurrency when the CPU usage is significantly below the minimum target" do
          lambda_client = lambda_client_with_concurrency(200)
          cloudwatch_client = cloudwatch_client_with_storage_metrics(required_free_storage_in_mb + 1)
          concurrency_scaler = build_concurrency_scaler(
            datastore_client: datastore_client_with_cpu_usage(10.0),
            sqs_client: sqs_client_with_number_of_messages(1),
            lambda_client: lambda_client,
            cloudwatch_client: cloudwatch_client
          )

          tune_indexer_concurrency(concurrency_scaler)

          expect(updated_concurrency_requested_from(lambda_client)).to eq [300] # 200 * 1.5
        end

        it "increases concurrency by a factor CPU usage when CPU is slightly below the minimum target" do
          # CPU is at 50% and our target range is 70-80. 75 / 50 = 1.5, so increase it by 50%.
          lambda_client = lambda_client_with_concurrency(200)
          cloudwatch_client = cloudwatch_client_with_storage_metrics(required_free_storage_in_mb + 1)
          concurrency_scaler = build_concurrency_scaler(
            datastore_client: datastore_client_with_cpu_usage(50.0),
            sqs_client: sqs_client_with_number_of_messages(1),
            lambda_client: lambda_client,
            cloudwatch_client: cloudwatch_client
          )

          tune_indexer_concurrency(concurrency_scaler)

          expect(updated_concurrency_requested_from(lambda_client)).to eq [300] # 200 + 50%
        end

        it "sets concurrency to the max when it cannot be increased anymore when CPU usage is under the limit" do
          current_concurrency = maximum_concurrency - 1
          lambda_client = lambda_client_with_concurrency(current_concurrency)
          cloudwatch_client = cloudwatch_client_with_storage_metrics(required_free_storage_in_mb + 1)
          concurrency_scaler = build_concurrency_scaler(
            datastore_client: datastore_client_with_cpu_usage(10),
            sqs_client: sqs_client_with_number_of_messages(1),
            lambda_client: lambda_client,
            cloudwatch_client: cloudwatch_client
          )

          tune_indexer_concurrency(concurrency_scaler)

          expect(updated_concurrency_requested_from(lambda_client)).to eq [1000] # maximum_concurrency = 1000
        end

        it "decreases concurrency by a factor of the CPU when the CPU usage is over the limit" do
          # CPU is at 90% and our target range is 70-80. 90 / 75 = 1.2, so decrease it by 20%.
          lambda_client = lambda_client_with_concurrency(500)
          cloudwatch_client = cloudwatch_client_with_storage_metrics(required_free_storage_in_mb + 1)
          concurrency_scaler = build_concurrency_scaler(
            datastore_client: datastore_client_with_cpu_usage(90.0),
            sqs_client: sqs_client_with_number_of_messages(1),
            lambda_client: lambda_client,
            cloudwatch_client: cloudwatch_client
          )

          tune_indexer_concurrency(concurrency_scaler)

          expect(updated_concurrency_requested_from(lambda_client)).to eq [400] # 500 - 20%
        end

        it "leaves concurrency unchanged when it cannot be decreased anymore when CPU utilization is over the limit" do
          current_concurrency = 0
          lambda_client = lambda_client_with_concurrency(current_concurrency)
          cloudwatch_client = cloudwatch_client_with_storage_metrics(required_free_storage_in_mb + 1)
          concurrency_scaler = build_concurrency_scaler(
            datastore_client: datastore_client_with_cpu_usage(100),
            sqs_client: sqs_client_with_number_of_messages(1),
            lambda_client: lambda_client,
            cloudwatch_client: cloudwatch_client
          )

          tune_indexer_concurrency(concurrency_scaler)

          expect(updated_concurrency_requested_from(lambda_client)).to eq []
        end

        it "does not adjust concurrency when the CPU is within the target range" do
          lambda_client = lambda_client_with_concurrency(500)
          cloudwatch_client = cloudwatch_client_with_storage_metrics(required_free_storage_in_mb + 1)
          [min_cpu_target, cpu_midpoint, max_cpu_target].each do |cpu_usage|
            concurrency_scaler = build_concurrency_scaler(
              datastore_client: datastore_client_with_cpu_usage(cpu_usage),
              sqs_client: sqs_client_with_number_of_messages(1),
              lambda_client: lambda_client,
              cloudwatch_client: cloudwatch_client
            )

            tune_indexer_concurrency(concurrency_scaler)
          end

          expect(updated_concurrency_requested_from(lambda_client)).to eq []
        end

        it "decreases the concurrency when at least one of the node's CPU is over the limit" do
          current_concurrency = 500
          high_cpu_usage = 81
          expect(high_cpu_usage).to be > max_cpu_target

          lambda_client = lambda_client_with_concurrency(current_concurrency)
          cloudwatch_client = cloudwatch_client_with_storage_metrics(required_free_storage_in_mb + 1)
          concurrency_scaler = build_concurrency_scaler(
            datastore_client: datastore_client_with_cpu_usage(min_cpu_target, high_cpu_usage),
            sqs_client: sqs_client_with_number_of_messages(1),
            lambda_client: lambda_client,
            cloudwatch_client: cloudwatch_client
          )

          tune_indexer_concurrency(concurrency_scaler)

          expect(high_cpu_usage).to be > max_cpu_target
          expect(updated_concurrency_requested_from(lambda_client)).to eq [460] # 500 - 8% since 81/75 = 1.08
        end

        it "pauses the concurrency when free storage space drops below the threshold regardless of cpu" do
          lambda_client = lambda_client_with_concurrency(500)
          cloudwatch_client = cloudwatch_client_with_storage_metrics(required_free_storage_in_mb - 1)
          concurrency_scaler = build_concurrency_scaler(
            datastore_client: datastore_client_with_cpu_usage(min_cpu_target - 1),
            sqs_client: sqs_client_with_number_of_messages(1),
            lambda_client: lambda_client,
            cloudwatch_client: cloudwatch_client
          )

          tune_indexer_concurrency(concurrency_scaler)

          expect(updated_concurrency_requested_from(lambda_client)).to eq [2] # 2 is the minimum
        end

        it "sets concurrency to the min when there are no messages in the queue" do
          current_concurrency = 500
          lambda_client = lambda_client_with_concurrency(current_concurrency)
          cloudwatch_client = cloudwatch_client_with_storage_metrics(required_free_storage_in_mb + 1)
          concurrency_scaler = build_concurrency_scaler(
            datastore_client: datastore_client_with_cpu_usage(min_cpu_target - 1),
            sqs_client: sqs_client_with_number_of_messages(0),
            lambda_client: lambda_client,
            cloudwatch_client: cloudwatch_client
          )

          tune_indexer_concurrency(concurrency_scaler)

          expect(updated_concurrency_requested_from(lambda_client)).to eq [2] # 2 is the minimum
        end

        it "leaves concurrency unset if it is currently unset" do
          lambda_client = lambda_client_without_concurrency
          cloudwatch_client = cloudwatch_client_with_storage_metrics(required_free_storage_in_mb + 1)

          # CPU is at 50% and our target range is 70-80.
          concurrency_scaler = build_concurrency_scaler(
            datastore_client: datastore_client_with_cpu_usage(50),
            sqs_client: sqs_client_with_number_of_messages(1),
            lambda_client: lambda_client,
            cloudwatch_client: cloudwatch_client
          )

          tune_indexer_concurrency(concurrency_scaler)

          expect(updated_concurrency_requested_from(lambda_client)).to eq []
        end
      end

      def updated_concurrency_requested_from(lambda_client)
        lambda_client.api_requests.filter_map do |req|
          if req.fetch(:operation_name) == :put_function_concurrency
            expect(indexer_function_name).to include(req.dig(:params, :function_name))
            req.dig(:params, :reserved_concurrent_executions)
          end
        end
      end

      def datastore_client_with_cpu_usage(percent, percent2 = percent)
        stubbed_datastore_client(get_node_os_stats: {
          "nodes" => {
            "node1" => {
              "os" => {
                "cpu" => {
                  "percent" => percent
                }
              }
            },
            "node2" => {
              "os" => {
                "cpu" => {
                  "percent" => percent2
                }
              }
            }
          }
        })
      end

      def sqs_client_with_number_of_messages(num_messages)
        ::Aws::SQS::Client.new(stub_responses: true).tap do |sqs_client|
          sqs_client.stub_responses(:get_queue_attributes, {
            attributes: {
              "ApproximateNumberOfMessages" => num_messages.to_s,
              "QueueArn" => "arn:aws:sqs:us-west-2:000000000:some-eg-app-queue-name"
            }
          })
        end
      end

      def lambda_client_with_concurrency(concurrency)
        ::Aws::Lambda::Client.new(stub_responses: true).tap do |lambda_client|
          lambda_client.stub_responses(:get_function_concurrency, {
            reserved_concurrent_executions: concurrency
          })
        end
      end

      def cloudwatch_client_with_storage_metrics(free_storage)
        ::Aws::CloudWatch::Client.new(stub_responses: true).tap do |cloudwatch_client|
          cloudwatch_client.stub_responses(:get_metric_data, {
            metric_data_results: [
              {
                id: "minFreeStorageAcrossNodes",
                values: [free_storage.to_f],
                timestamps: [::Time.parse("2024-10-30T12:00:00Z")]
              }
            ]
          })
        end
      end

      # If the lambda is using unreserved concurrency, reserved_concurrent_executions on the Lambda client will be nil.
      def lambda_client_without_concurrency
        ::Aws::Lambda::Client.new(stub_responses: true).tap do |lambda_client|
          lambda_client.stub_responses(:get_function_concurrency, {
            reserved_concurrent_executions: nil
          })
        end
      end

      def build_concurrency_scaler(datastore_client:, sqs_client:, lambda_client:, cloudwatch_client:)
        build_indexer_autoscaler(
          clients_by_name: {"main" => datastore_client},
          sqs_client: sqs_client,
          lambda_client: lambda_client,
          cloudwatch_client: cloudwatch_client
        ).concurrency_scaler
      end

      def tune_indexer_concurrency(concurrency_scaler)
        concurrency_scaler.tune_indexer_concurrency(
          queue_urls: ["https://sqs.us-west-2.amazonaws.com/000000000/some-eg-app-queue-name"],
          min_cpu_target: min_cpu_target,
          max_cpu_target: max_cpu_target,
          maximum_concurrency: maximum_concurrency,
          required_free_storage_in_mb: required_free_storage_in_mb,
          indexer_function_name: indexer_function_name,
          cluster_name: "some-eg-cluster"
        )
      end
    end
  end
end
