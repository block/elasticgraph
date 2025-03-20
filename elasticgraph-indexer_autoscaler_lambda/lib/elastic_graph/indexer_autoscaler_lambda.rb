# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/datastore_core"
require "elastic_graph/lambda_support"
require "elastic_graph/support/from_yaml_file"

module ElasticGraph
  # @private
  class IndexerAutoscalerLambda
    extend Support::FromYamlFile

    # Builds an `ElasticGraph::IndexerAutoscalerLambda` instance from our lambda ENV vars.
    def self.from_env
      LambdaSupport.build_from_env(self)
    end

    # A factory method that builds a IndexerAutoscalerLambda instance from the given parsed YAML config.
    # `from_yaml_file(file_name, &block)` is also available (via `Support::FromYamlFile`).
    def self.from_parsed_yaml(parsed_yaml, &datastore_client_customization_block)
      new(datastore_core: DatastoreCore.from_parsed_yaml(parsed_yaml, for_context: :indexer_autoscaler_lambda, &datastore_client_customization_block))
    end

    # @dynamic datastore_core
    attr_reader :datastore_core

    def initialize(
      datastore_core:,
      sqs_client: nil,
      lambda_client: nil,
      cloudwatch_client: nil
    )
      @datastore_core = datastore_core
      @sqs_client = sqs_client
      @lambda_client = lambda_client
      @cloudwatch_client = cloudwatch_client
    end

    def sqs_client
      @sqs_client ||= begin
        require "aws-sdk-sqs"
        Aws::SQS::Client.new
      end
    end

    def lambda_client
      @lambda_client ||= begin
        require "aws-sdk-lambda"
        Aws::Lambda::Client.new
      end
    end

    def cloudwatch_client
      @cloudwatch_client ||= begin
        require "aws-sdk-cloudwatch"
        Aws::CloudWatch::Client.new
      end
    end

    def concurrency_scaler
      @concurrency_scaler ||= begin
        require "elastic_graph/indexer_autoscaler_lambda/concurrency_scaler"
        ConcurrencyScaler.new(
          datastore_core: @datastore_core,
          sqs_client: sqs_client,
          lambda_client: lambda_client,
          cloudwatch_client: cloudwatch_client
        )
      end
    end
  end
end
