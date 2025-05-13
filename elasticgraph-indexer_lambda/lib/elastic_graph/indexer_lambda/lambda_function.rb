# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/lambda_support/lambda_function"

module ElasticGraph
  module IndexerLambda
    # @private
    class LambdaFunction
      prepend LambdaSupport::LambdaFunction

      def initialize
        require "elastic_graph/indexer_lambda"
        require "elastic_graph/indexer_lambda/sqs_processor"

        indexer = ElasticGraph::IndexerLambda.indexer_from_env
        @sqs_processor = ElasticGraph::IndexerLambda::SqsProcessor.new(indexer.processor, logger: indexer.logger)
      end

      def handle_request(event:, context:)
        @sqs_processor.process(event)
      end
    end
  end
end

# Lambda handler for `elasticgraph-indexer_lambda`.
ProcessEventStreamEvent = ElasticGraph::IndexerLambda::LambdaFunction.new
