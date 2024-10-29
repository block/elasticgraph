# Copyright 2024 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/indexer_autoscaler_lambda/details_logger"

module ElasticGraph
  class IndexerAutoscalerLambda
    # @private
    class ConcurrencyScaler
      def initialize(datastore_core:, sqs_client:, lambda_client:)
        @logger = datastore_core.logger
        @datastore_core = datastore_core
        @sqs_client = sqs_client
        @lambda_client = lambda_client
      end

      MINIMUM_CONCURRENCY = 2

      def tune_indexer_concurrency(queue_urls:, min_cpu_target:, max_cpu_target:, maximum_concurrency:, indexer_function_name:)
        queue_attributes = get_queue_attributes(queue_urls)
        queue_arns = queue_attributes.fetch(:queue_arns)
        num_messages = queue_attributes.fetch(:total_messages)

        details_logger = DetailsLogger.new(
          logger: @logger,
          queue_arns: queue_arns,
          queue_urls: queue_urls,
          min_cpu_target: min_cpu_target,
          max_cpu_target: max_cpu_target,
          num_messages: num_messages
        )

        new_target_concurrency =
          if num_messages.positive?
            cpu_utilization = get_max_cpu_utilization
            cpu_midpoint = (max_cpu_target + min_cpu_target) / 2.0

            current_concurrency = get_concurrency(indexer_function_name)

            if current_concurrency.nil?
              details_logger.log_unset
              nil
            elsif cpu_utilization < min_cpu_target
              increase_factor = (cpu_midpoint / cpu_utilization).clamp(0.0, 1.5)
              (current_concurrency * increase_factor).round.tap do |new_concurrency|
                details_logger.log_increase(
                  cpu_utilization: cpu_utilization,
                  current_concurrency: current_concurrency,
                  new_concurrency: new_concurrency
                )
              end
            elsif cpu_utilization > max_cpu_target
              decrease_factor = cpu_utilization / cpu_midpoint - 1
              (current_concurrency - (current_concurrency * decrease_factor)).round.tap do |new_concurrency|
                details_logger.log_decrease(
                  cpu_utilization: cpu_utilization,
                  current_concurrency: current_concurrency,
                  new_concurrency: new_concurrency
                )
              end
            else
              details_logger.log_no_change(
                cpu_utilization: cpu_utilization,
                current_concurrency: current_concurrency
              )
              current_concurrency
            end
          else
            details_logger.log_reset
            0
          end

        if new_target_concurrency && new_target_concurrency != current_concurrency
          update_concurrency(
            indexer_function_name: indexer_function_name,
            concurrency: new_target_concurrency,
            maximum_concurrency: maximum_concurrency
          )
        end
      end

      private

      def get_max_cpu_utilization
        @datastore_core.clients_by_name.values.flat_map do |client|
          client.get_node_os_stats.fetch("nodes").values.map do |node|
            node.dig("os", "cpu", "percent")
          end
        end.max.to_f
      end

      def get_queue_attributes(queue_urls)
        attributes_per_queue = queue_urls.map do |queue_url|
          @sqs_client.get_queue_attributes(
            queue_url: queue_url,
            attribute_names: ["QueueArn", "ApproximateNumberOfMessages"]
          ).attributes
        end

        total_messages = attributes_per_queue
          .map { |attr| Integer(attr.fetch("ApproximateNumberOfMessages")) }
          .sum

        queue_arns = attributes_per_queue.map { |attr| attr.fetch("QueueArn") }

        {
          total_messages: total_messages,
          queue_arns: queue_arns
        }
      end

      def get_concurrency(indexer_function_name)
        @lambda_client.get_function_concurrency(
          function_name: indexer_function_name
        ).reserved_concurrent_executions
      end

      def update_concurrency(indexer_function_name:, concurrency:, maximum_concurrency:)
        target_concurrency = concurrency.clamp(MINIMUM_CONCURRENCY, maximum_concurrency)
        @lambda_client.put_function_concurrency(
          function_name: indexer_function_name,
          reserved_concurrent_executions: target_concurrency
        )
      end
    end
  end
end
