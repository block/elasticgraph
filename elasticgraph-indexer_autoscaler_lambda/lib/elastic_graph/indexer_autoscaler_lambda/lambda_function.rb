# Copyright 2024 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/lambda_support/lambda_function"

module ElasticGraph
  class IndexerAutoscalerLambda
    # @private
    class LambdaFunction
      prepend LambdaSupport::LambdaFunction

      def initialize
        require "elastic_graph/indexer_autoscaler_lambda"

        @concurrency_scaler = ElasticGraph::IndexerAutoscalerLambda.from_env.concurrency_scaler
      end

      def handle_request(event:, context:)
        @concurrency_scaler.tune_indexer_concurrency(
          queue_urls: event.fetch("queue_urls"),
          min_cpu_target: event.fetch("min_cpu_target"),
          max_cpu_target: event.fetch("max_cpu_target"),
          maximum_concurrency: event.fetch("maximum_concurrency"),
          required_free_storage_in_mb: event.fetch("required_free_storage_in_mb"),
          indexer_function_name: event.fetch("indexer_function_name"),
          cluster_name: event.fetch("cluster_name")
        )
      end
    end
  end
end

# Lambda handler for `elasticgraph-indexer_autoscaler_lambda`.
AutoscaleIndexer = ElasticGraph::IndexerAutoscalerLambda::LambdaFunction.new
