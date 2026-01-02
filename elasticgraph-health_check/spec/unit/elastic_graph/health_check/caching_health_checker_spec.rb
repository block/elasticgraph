# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/health_check/caching_health_checker"
require "elastic_graph/health_check/health_status"

module ElasticGraph
  module HealthCheck
    # A simple clock class that can be controlled for testing
    class FakeClock
      attr_accessor :current_time

      def initialize(time)
        @current_time = time
      end

      def now
        @current_time
      end
    end

    RSpec.describe CachingHealthChecker do
      let(:base_time) { ::Time.utc(2024, 1, 1, 12, 0, 0) }
      let(:health_checker) { instance_double("HealthChecker") }
      let(:clock) { FakeClock.new(base_time) }

      def build_health_status(category)
        HealthStatus.new(
          cluster_health_by_name: {"main" => build_cluster_health((category == :unhealthy) ? "red" : "green")},
          latest_record_by_type: {}
        )
      end

      def build_cluster_health(status)
        HealthStatus::ClusterHealth.new(
          cluster_name: "main",
          status: status,
          timed_out: false,
          number_of_nodes: 3,
          number_of_data_nodes: 3,
          active_primary_shards: 10,
          active_shards: 20,
          relocating_shards: 0,
          initializing_shards: 0,
          unassigned_shards: 0,
          delayed_unassigned_shards: 0,
          number_of_pending_tasks: 0,
          number_of_in_flight_fetch: 0,
          task_max_waiting_in_queue_millis: 0,
          active_shards_percent_as_number: 100.0,
          discovered_master: true
        )
      end

      describe "when caching is disabled (both TTLs are 0)" do
        it "always calls the underlying health checker" do
          caching_checker = CachingHealthChecker.new(
            health_checker: health_checker,
            healthy_ttl_seconds: 0,
            unhealthy_ttl_seconds: 0,
            clock: clock
          )

          healthy_status = build_health_status(:healthy)
          allow(health_checker).to receive(:check_health).and_return(healthy_status)

          result1 = caching_checker.check_health
          result2 = caching_checker.check_health
          result3 = caching_checker.check_health

          expect(health_checker).to have_received(:check_health).exactly(3).times
          expect(result1).to eq(healthy_status)
          expect(result2).to eq(healthy_status)
          expect(result3).to eq(healthy_status)
        end
      end

      describe "when healthy_ttl_seconds is configured" do
        it "caches healthy results for the configured duration" do
          caching_checker = CachingHealthChecker.new(
            health_checker: health_checker,
            healthy_ttl_seconds: 30,
            unhealthy_ttl_seconds: 0,
            clock: clock
          )

          healthy_status = build_health_status(:healthy)
          allow(health_checker).to receive(:check_health).and_return(healthy_status)

          # First call at t=0
          clock.current_time = base_time
          result1 = caching_checker.check_health

          # Second call at t=15 (within TTL) - should use cache
          clock.current_time = base_time + 15
          result2 = caching_checker.check_health

          # Third call at t=29 (still within TTL) - should use cache
          clock.current_time = base_time + 29
          result3 = caching_checker.check_health

          expect(health_checker).to have_received(:check_health).once
          expect(result1).to eq(healthy_status)
          expect(result2).to eq(healthy_status)
          expect(result3).to eq(healthy_status)
        end

        it "refreshes the cache after the TTL expires" do
          caching_checker = CachingHealthChecker.new(
            health_checker: health_checker,
            healthy_ttl_seconds: 30,
            unhealthy_ttl_seconds: 0,
            clock: clock
          )

          healthy_status1 = build_health_status(:healthy)
          healthy_status2 = build_health_status(:healthy)
          allow(health_checker).to receive(:check_health).and_return(healthy_status1, healthy_status2)

          # First call at t=0
          clock.current_time = base_time
          result1 = caching_checker.check_health

          # Second call at t=30 (TTL expired) - should refresh
          clock.current_time = base_time + 30
          result2 = caching_checker.check_health

          expect(health_checker).to have_received(:check_health).twice
          expect(result1).to eq(healthy_status1)
          expect(result2).to eq(healthy_status2)
        end

        it "does not cache unhealthy results when unhealthy_ttl_seconds is 0" do
          caching_checker = CachingHealthChecker.new(
            health_checker: health_checker,
            healthy_ttl_seconds: 30,
            unhealthy_ttl_seconds: 0,
            clock: clock
          )

          unhealthy_status = build_health_status(:unhealthy)
          allow(health_checker).to receive(:check_health).and_return(unhealthy_status)
          clock.current_time = base_time

          result1 = caching_checker.check_health
          result2 = caching_checker.check_health

          expect(health_checker).to have_received(:check_health).twice
          expect(result1).to eq(unhealthy_status)
          expect(result2).to eq(unhealthy_status)
        end
      end

      describe "when unhealthy_ttl_seconds is configured" do
        it "caches unhealthy results for the configured duration" do
          caching_checker = CachingHealthChecker.new(
            health_checker: health_checker,
            healthy_ttl_seconds: 0,
            unhealthy_ttl_seconds: 5,
            clock: clock
          )

          unhealthy_status = build_health_status(:unhealthy)
          allow(health_checker).to receive(:check_health).and_return(unhealthy_status)

          # First call at t=0
          clock.current_time = base_time
          result1 = caching_checker.check_health

          # Second call at t=3 (within TTL) - should use cache
          clock.current_time = base_time + 3
          result2 = caching_checker.check_health

          # Third call at t=4.9 (still within TTL) - should use cache
          clock.current_time = base_time + 4.9
          result3 = caching_checker.check_health

          expect(health_checker).to have_received(:check_health).once
          expect(result1).to eq(unhealthy_status)
          expect(result2).to eq(unhealthy_status)
          expect(result3).to eq(unhealthy_status)
        end

        it "refreshes the cache after the unhealthy TTL expires" do
          caching_checker = CachingHealthChecker.new(
            health_checker: health_checker,
            healthy_ttl_seconds: 0,
            unhealthy_ttl_seconds: 5,
            clock: clock
          )

          unhealthy_status1 = build_health_status(:unhealthy)
          unhealthy_status2 = build_health_status(:unhealthy)
          allow(health_checker).to receive(:check_health).and_return(unhealthy_status1, unhealthy_status2)

          # First call at t=0
          clock.current_time = base_time
          result1 = caching_checker.check_health

          # Second call at t=5 (TTL expired) - should refresh
          clock.current_time = base_time + 5
          result2 = caching_checker.check_health

          expect(health_checker).to have_received(:check_health).twice
          expect(result1).to eq(unhealthy_status1)
          expect(result2).to eq(unhealthy_status2)
        end

        it "does not cache healthy results when healthy_ttl_seconds is 0" do
          caching_checker = CachingHealthChecker.new(
            health_checker: health_checker,
            healthy_ttl_seconds: 0,
            unhealthy_ttl_seconds: 5,
            clock: clock
          )

          healthy_status = build_health_status(:healthy)
          allow(health_checker).to receive(:check_health).and_return(healthy_status)
          clock.current_time = base_time

          result1 = caching_checker.check_health
          result2 = caching_checker.check_health

          expect(health_checker).to have_received(:check_health).twice
          expect(result1).to eq(healthy_status)
          expect(result2).to eq(healthy_status)
        end

        it "caches degraded results using the unhealthy TTL" do
          caching_checker = CachingHealthChecker.new(
            health_checker: health_checker,
            healthy_ttl_seconds: 30,
            unhealthy_ttl_seconds: 5,
            clock: clock
          )

          # Create a degraded status (yellow cluster)
          degraded_status = HealthStatus.new(
            cluster_health_by_name: {"main" => build_cluster_health("yellow")},
            latest_record_by_type: {}
          )
          expect(degraded_status.category).to eq(:degraded)

          allow(health_checker).to receive(:check_health).and_return(degraded_status)

          # First call at t=0
          clock.current_time = base_time
          result1 = caching_checker.check_health

          # Second call at t=3 (within unhealthy TTL) - should use cache
          clock.current_time = base_time + 3
          result2 = caching_checker.check_health

          expect(health_checker).to have_received(:check_health).once
          expect(result1).to eq(degraded_status)
          expect(result2).to eq(degraded_status)
        end
      end

      describe "when both TTLs are configured" do
        it "uses healthy_ttl_seconds for healthy results and unhealthy_ttl_seconds for unhealthy results" do
          caching_checker = CachingHealthChecker.new(
            health_checker: health_checker,
            healthy_ttl_seconds: 30,
            unhealthy_ttl_seconds: 5,
            clock: clock
          )

          healthy_status = build_health_status(:healthy)
          unhealthy_status = build_health_status(:unhealthy)

          # First: healthy result
          allow(health_checker).to receive(:check_health).and_return(healthy_status)
          clock.current_time = base_time
          result1 = caching_checker.check_health

          # At t=25, still within healthy TTL - should use cache
          clock.current_time = base_time + 25
          result2 = caching_checker.check_health

          expect(health_checker).to have_received(:check_health).once
          expect(result1.category).to eq(:healthy)
          expect(result2.category).to eq(:healthy)

          # At t=30, healthy TTL expired - should refresh
          allow(health_checker).to receive(:check_health).and_return(unhealthy_status)
          clock.current_time = base_time + 30
          result3 = caching_checker.check_health

          expect(health_checker).to have_received(:check_health).twice
          expect(result3.category).to eq(:unhealthy)

          # At t=33, within unhealthy TTL - should use cache
          clock.current_time = base_time + 33
          result4 = caching_checker.check_health

          expect(health_checker).to have_received(:check_health).twice
          expect(result4.category).to eq(:unhealthy)

          # At t=35, unhealthy TTL expired - should refresh
          allow(health_checker).to receive(:check_health).and_return(healthy_status)
          clock.current_time = base_time + 35
          result5 = caching_checker.check_health

          expect(health_checker).to have_received(:check_health).exactly(3).times
          expect(result5.category).to eq(:healthy)
        end
      end

      describe "thread safety" do
        it "is thread-safe when multiple threads call check_health concurrently" do
          caching_checker = CachingHealthChecker.new(
            health_checker: health_checker,
            healthy_ttl_seconds: 30,
            unhealthy_ttl_seconds: 5,
            clock: clock
          )

          healthy_status = build_health_status(:healthy)
          call_count = 0

          clock.current_time = base_time
          allow(health_checker).to receive(:check_health) do
            call_count += 1
            sleep(0.01) # Small delay to increase chance of race conditions
            healthy_status
          end

          threads = 10.times.map do
            Thread.new { caching_checker.check_health }
          end

          results = threads.map(&:value)

          # All results should be the same healthy status
          expect(results).to all(eq(healthy_status))

          # Due to mutex, only one call should have been made (or possibly 2 if timing is unlucky)
          expect(call_count).to be <= 2
        end
      end
    end
  end
end
