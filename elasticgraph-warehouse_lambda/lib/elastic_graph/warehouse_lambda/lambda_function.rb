# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/lambda_support/lambda_function"
require "json"

module ElasticGraph
  class WarehouseLambda
    # @private
    class LambdaFunction
      prepend LambdaSupport::LambdaFunction

      # @dynamic sqs_processor
      attr_reader :sqs_processor

      def initialize
        require "elastic_graph/warehouse_lambda"
        require "elastic_graph/indexer_lambda/sqs_processor"

        warehouse_lambda = WarehouseLambda.warehouse_lambda_from_env
        ignore_sqs_latency_timestamps_from_arns = ::JSON.parse(ENV.fetch("IGNORE_SQS_LATENCY_TIMESTAMPS_FROM_ARNS", "[]")).to_set

        @sqs_processor = IndexerLambda::SqsProcessor.new(
          warehouse_lambda.processor,
          ignore_sqs_latency_timestamps_from_arns: ignore_sqs_latency_timestamps_from_arns,
          logger: warehouse_lambda.logger
        )
      end

      def handle_request(event:, context:)
        @sqs_processor.process(event)
      end
    end
  end
end

# Lambda handler for `elasticgraph-warehouse_lambda`.
DumpWarehouseData = ElasticGraph::WarehouseLambda::LambdaFunction.new
