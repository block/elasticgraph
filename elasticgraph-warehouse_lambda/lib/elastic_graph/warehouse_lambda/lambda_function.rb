# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/lambda_support/lambda_function"

module ElasticGraph
  class WarehouseLambda
    # @private
    class LambdaFunction
      prepend ::ElasticGraph::LambdaSupport::LambdaFunction

      def initialize
        require "elastic_graph/warehouse_lambda"
        require "elastic_graph/indexer_lambda/sqs_processor"

        warehouse_lambda = WarehouseLambda.from_env
        @sqs_processor = ::ElasticGraph::IndexerLambda::SqsProcessor.new(
          warehouse_lambda.processor,
          logger: warehouse_lambda.logger,
          ignore_sqs_latency_timestamps_from_arns: JSON.parse(ENV.fetch("IGNORE_SQS_LATENCY_TIMESTAMPS_FROM_ARNS", "[]")).to_set
        )
      end

      def handle_request(event:, context:)
        @sqs_processor.process(event)
      end
    end
  end
end

# Lambda handler for `elasticgraph-warehouse_lambda`.
ElasticGraphWarehouse = ElasticGraph::WarehouseLambda::LambdaFunction.new
