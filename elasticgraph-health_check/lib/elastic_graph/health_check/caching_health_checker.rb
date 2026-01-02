# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  module HealthCheck
    # Wraps a HealthChecker to provide caching of health check results.
    # Healthy results can be cached for a longer duration (healthy_ttl_seconds),
    # while unhealthy/degraded results are cached for a shorter duration (unhealthy_ttl_seconds).
    class CachingHealthChecker
      def initialize(health_checker:, healthy_ttl_seconds:, unhealthy_ttl_seconds:, clock:)
        @health_checker = health_checker
        @healthy_ttl_seconds = healthy_ttl_seconds
        @unhealthy_ttl_seconds = unhealthy_ttl_seconds
        @clock = clock
        @mutex = ::Mutex.new
        @cached_status = nil
        @cache_expires_at = nil
      end

      def check_health
        @mutex.synchronize do
          now = @clock.now

          if @cached_status && @cache_expires_at && now < @cache_expires_at
            return @cached_status
          end

          status = @health_checker.check_health
          ttl = (status.category == :healthy) ? @healthy_ttl_seconds : @unhealthy_ttl_seconds

          if ttl > 0
            @cached_status = status
            @cache_expires_at = now + ttl
          else
            @cached_status = nil
            @cache_expires_at = nil
          end

          status
        end
      end
    end
  end
end
