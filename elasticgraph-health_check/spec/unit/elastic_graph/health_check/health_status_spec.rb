# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/health_check/health_status"
require "time"

module ElasticGraph
  module HealthCheck
    RSpec.describe HealthStatus do
      let(:new_enough_latest_record) { HealthStatus::LatestRecord.new("abc", ::Time.iso8601("2022-03-12T12:30:00Z"), 10) }
      let(:too_old_latest_record) { HealthStatus::LatestRecord.new("abc", ::Time.iso8601("2022-03-12T12:30:00Z"), -12) }
      let(:exact_moment_latest_record) { HealthStatus::LatestRecord.new("abc", ::Time.iso8601("2022-03-12T12:30:00Z"), 0) }

      let(:example_cluster_health) do
        HealthStatus::ClusterHealth.new(
          cluster_name: "my_cluster",
          status: "green",
          timed_out: false,
          number_of_nodes: 1,
          number_of_data_nodes: 2,
          active_primary_shards: 3,
          active_shards: 4,
          relocating_shards: 5,
          initializing_shards: 6,
          unassigned_shards: 7,
          delayed_unassigned_shards: 8,
          number_of_pending_tasks: 9,
          number_of_in_flight_fetch: 10,
          task_max_waiting_in_queue_millis: 11,
          active_shards_percent_as_number: 50.0,
          discovered_master: true
        )
      end

      describe "#category" do
        context "when the status is empty (as happens when the health check is not configured)" do
          it "returns :healthy as the safest default return value" do
            status = HealthStatus.new(cluster_health_by_name: {}, latest_record_by_type: {})

            expect(status.category).to eq :healthy
          end
        end

        context "when one of the clusters has a red status" do
          it "returns :unhealthy, regardless of other clusters or latest records" do
            status = HealthStatus.new(
              cluster_health_by_name: {
                "main" => example_cluster_health.with(status: "green"),
                "other1" => example_cluster_health.with(status: "red"),
                "other2" => example_cluster_health.with(status: "yellow")
              },
              latest_record_by_type: {
                "Widget" => new_enough_latest_record
              }
            )

            expect(status.category).to eq :unhealthy
          end
        end

        context "when one of the clusters has a yellow status (and no clusters have a red status)" do
          it "returns :degraded, regardless of other clusters or latest records" do
            status = HealthStatus.new(
              cluster_health_by_name: {
                "main" => example_cluster_health.with(status: "green"),
                "other1" => example_cluster_health.with(status: "yellow")
              },
              latest_record_by_type: {
                "Widget" => new_enough_latest_record
              }
            )

            expect(status.category).to eq :degraded
          end
        end

        context "when one of the latest records is older than expected" do
          it "returns :degraded, regardless of other latest records, so long as no clusters are red" do
            status = HealthStatus.new(
              cluster_health_by_name: {
                "main" => example_cluster_health.with(status: "green"),
                "other1" => example_cluster_health.with(status: "green")
              },
              latest_record_by_type: {
                "Widget" => too_old_latest_record,
                "Component" => new_enough_latest_record
              }
            )

            expect(status.category).to eq :degraded
          end
        end

        context "when one of the latest records is nil" do
          it "returns :degraded, regardless of other latest records, so long as no clusters are red" do
            status = HealthStatus.new(
              cluster_health_by_name: {
                "main" => example_cluster_health.with(status: "green"),
                "other1" => example_cluster_health.with(status: "green")
              },
              latest_record_by_type: {
                "Widget" => nil,
                "Component" => new_enough_latest_record
              }
            )

            expect(status.category).to eq :degraded
          end
        end

        context "when all the clusters green and all the latest records are new enough" do
          it "returns :healthy" do
            status = HealthStatus.new(
              cluster_health_by_name: {
                "main" => example_cluster_health.with(status: "green"),
                "other1" => example_cluster_health.with(status: "green")
              },
              latest_record_by_type: {
                "Widget" => new_enough_latest_record,
                "Component" => new_enough_latest_record
              }
            )

            expect(status.category).to eq :healthy
          end

          it "considers a record that's exactly as old as the threshold to be new enough" do
            status = HealthStatus.new(
              cluster_health_by_name: {
                "main" => example_cluster_health.with(status: "green"),
                "other1" => example_cluster_health.with(status: "green")
              },
              latest_record_by_type: {
                "Widget" => new_enough_latest_record,
                "Component" => exact_moment_latest_record
              }
            )

            expect(status.category).to eq :healthy
          end
        end

        describe "#to_loggable_description" do
          it "generates a readable description of the status details" do
            status = HealthStatus.new(
              cluster_health_by_name: {
                "main" => example_cluster_health.with(status: "green"),
                "other1" => example_cluster_health.with(status: "yellow")
              },
              latest_record_by_type: {
                "Widget" => new_enough_latest_record,
                "Component" => exact_moment_latest_record
              }
            )

            expect(status.to_loggable_description).to eq(<<~EOS.strip)
              HealthStatus: degraded (checked 2 clusters, 2 latest records)
              - Latest Component (recent enough): abc / 2022-03-12T12:30:00Z (0s newer than required)
              - Latest Widget (recent enough): abc / 2022-03-12T12:30:00Z (10s newer than required)

              - main cluster health (green):
                cluster_name: "my_cluster"
                status: "green"
                timed_out: false
                number_of_nodes: 1
                number_of_data_nodes: 2
                active_primary_shards: 3
                active_shards: 4
                relocating_shards: 5
                initializing_shards: 6
                unassigned_shards: 7
                delayed_unassigned_shards: 8
                number_of_pending_tasks: 9
                number_of_in_flight_fetch: 10
                task_max_waiting_in_queue_millis: 11
                active_shards_percent_as_number: 50.0
                discovered_master: true

              - other1 cluster health (yellow):
                cluster_name: "my_cluster"
                status: "yellow"
                timed_out: false
                number_of_nodes: 1
                number_of_data_nodes: 2
                active_primary_shards: 3
                active_shards: 4
                relocating_shards: 5
                initializing_shards: 6
                unassigned_shards: 7
                delayed_unassigned_shards: 8
                number_of_pending_tasks: 9
                number_of_in_flight_fetch: 10
                task_max_waiting_in_queue_millis: 11
                active_shards_percent_as_number: 50.0
                discovered_master: true
            EOS
          end

          it "distinguishes between records that are too old, recent enough, or missing (and can skip the cluster health info if not available)" do
            status = HealthStatus.new(
              cluster_health_by_name: {},
              latest_record_by_type: {
                "Widget" => new_enough_latest_record,
                "Component" => too_old_latest_record,
                "Part" => nil
              }
            )

            expect(status.to_loggable_description).to eq(<<~EOS.strip)
              HealthStatus: degraded (checked 0 clusters, 3 latest records)
              - Latest Component (too old): abc / 2022-03-12T12:30:00Z (12s too old)
              - Latest Part (missing)
              - Latest Widget (recent enough): abc / 2022-03-12T12:30:00Z (10s newer than required)
            EOS
          end

          it "can skip the latest record info if not available" do
            status = HealthStatus.new(
              cluster_health_by_name: {
                "main" => example_cluster_health.with(status: "green"),
                "other1" => example_cluster_health.with(status: "yellow")
              },
              latest_record_by_type: {}
            )

            expect(status.to_loggable_description).to eq(<<~EOS.strip)
              HealthStatus: degraded (checked 2 clusters, 0 latest records)
              - main cluster health (green):
                cluster_name: "my_cluster"
                status: "green"
                timed_out: false
                number_of_nodes: 1
                number_of_data_nodes: 2
                active_primary_shards: 3
                active_shards: 4
                relocating_shards: 5
                initializing_shards: 6
                unassigned_shards: 7
                delayed_unassigned_shards: 8
                number_of_pending_tasks: 9
                number_of_in_flight_fetch: 10
                task_max_waiting_in_queue_millis: 11
                active_shards_percent_as_number: 50.0
                discovered_master: true

              - other1 cluster health (yellow):
                cluster_name: "my_cluster"
                status: "yellow"
                timed_out: false
                number_of_nodes: 1
                number_of_data_nodes: 2
                active_primary_shards: 3
                active_shards: 4
                relocating_shards: 5
                initializing_shards: 6
                unassigned_shards: 7
                delayed_unassigned_shards: 8
                number_of_pending_tasks: 9
                number_of_in_flight_fetch: 10
                task_max_waiting_in_queue_millis: 11
                active_shards_percent_as_number: 50.0
                discovered_master: true
            EOS
          end
        end
      end
    end
  end
end
