# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  class IndexerAutoscalerLambda
    # @private
    class DetailsLogger
      def initialize(
        logger:,
        queue_arns:,
        queue_urls:,
        min_cpu_target:,
        max_cpu_target:,
        num_messages:
      )
        @logger = logger

        @log_data = {
          "message_type" => "ConcurrencyScalerResult",
          "queue_arns" => queue_arns,
          "queue_urls" => queue_urls,
          "min_cpu_target" => min_cpu_target,
          "max_cpu_target" => max_cpu_target,
          "num_messages" => num_messages
        }
      end

      def log_increase(cpu_utilization:, lowest_node_free_storage_in_mb:, required_free_storage_in_mb:, current_concurrency:, new_concurrency:)
        log_result({
          "action" => "increase",
          "cpu_utilization" => cpu_utilization,
          "lowest_node_free_storage_in_mb" => lowest_node_free_storage_in_mb,
          "required_free_storage_in_mb" => required_free_storage_in_mb,
          "current_concurrency" => current_concurrency,
          "new_concurrency" => new_concurrency
        })
      end

      def log_decrease(cpu_utilization:, lowest_node_free_storage_in_mb:, required_free_storage_in_mb:, current_concurrency:, new_concurrency:)
        log_result({
          "action" => "decrease",
          "cpu_utilization" => cpu_utilization,
          "lowest_node_free_storage_in_mb" => lowest_node_free_storage_in_mb,
          "required_free_storage_in_mb" => required_free_storage_in_mb,
          "current_concurrency" => current_concurrency,
          "new_concurrency" => new_concurrency
        })
      end

      def log_no_change(cpu_utilization:, lowest_node_free_storage_in_mb:, required_free_storage_in_mb:, current_concurrency:)
        log_result({
          "action" => "no_change",
          "cpu_utilization" => cpu_utilization,
          "lowest_node_free_storage_in_mb" => lowest_node_free_storage_in_mb,
          "required_free_storage_in_mb" => required_free_storage_in_mb,
          "current_concurrency" => current_concurrency
        })
      end

      def log_pause(lowest_node_free_storage_in_mb:, required_free_storage_in_mb:)
        log_result({
          "action" => "pause",
          "lowest_node_free_storage_in_mb" => lowest_node_free_storage_in_mb,
          "required_free_storage_in_mb" => required_free_storage_in_mb
        })
      end

      def log_reset
        log_result({"action" => "reset"})
      end

      def log_unset
        log_result({"action" => "unset"})
      end

      private

      def log_result(data)
        @logger.info(@log_data.merge(data))
      end
    end
  end
end
