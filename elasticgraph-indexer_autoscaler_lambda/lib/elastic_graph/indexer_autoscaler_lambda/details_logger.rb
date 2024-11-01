# Copyright 2024 Block, Inc.
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

      def log_increase(cpu_utilization:, min_free_storage:, current_concurrency:, new_concurrency:)
        log_result({
          "action" => "increase",
          "cpu_utilization" => cpu_utilization,
          "min_free_storage" => min_free_storage,
          "current_concurrency" => current_concurrency,
          "new_concurrency" => new_concurrency
        })
      end

      def log_decrease(cpu_utilization:, min_free_storage:, current_concurrency:, new_concurrency:)
        log_result({
          "action" => "decrease",
          "cpu_utilization" => cpu_utilization,
          "min_free_storage" => min_free_storage,
          "current_concurrency" => current_concurrency,
          "new_concurrency" => new_concurrency
        })
      end

      def log_no_change(cpu_utilization:, min_free_storage:, current_concurrency:)
        log_result({
          "action" => "no_change",
          "cpu_utilization" => cpu_utilization,
          "min_free_storage" => min_free_storage,
          "current_concurrency" => current_concurrency
        })
      end

      def log_pause(min_free_storage)
        log_result({
          "action" => "pause",
          "min_free_storage" => min_free_storage
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
