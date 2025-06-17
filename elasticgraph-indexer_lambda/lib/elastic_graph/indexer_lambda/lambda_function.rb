# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/lambda_support/lambda_function"
require "json"

module ElasticGraph
  module IndexerLambda
    # @private
    class LambdaFunction
      prepend LambdaSupport::LambdaFunction

      # @dynamic sqs_processor
      attr_reader :sqs_processor

      def initialize
        require "elastic_graph/indexer_lambda"
        require "elastic_graph/indexer_lambda/sqs_processor"

        indexer = ElasticGraph::IndexerLambda.indexer_from_env
        ignore_sqs_latency_timestamps_from_arns = ::JSON.parse(ENV.fetch("IGNORE_SQS_LATENCY_TIMESTAMPS_FROM_ARNS", "[]")).to_set

        @sqs_processor = ElasticGraph::IndexerLambda::SqsProcessor.new(
          indexer.processor,
          ignore_sqs_latency_timestamps_from_arns: ignore_sqs_latency_timestamps_from_arns,
          logger: indexer.logger
        )
      end

      def handle_request(event:, context:)
        @sqs_processor.process(event)
      end
    end
  end
end

# Lambda handler for `elasticgraph-indexer_lambda`.
ProcessEventStreamEvent = ElasticGraph::IndexerLambda::LambdaFunction.new
