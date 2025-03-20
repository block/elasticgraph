# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/health_check/health_checker"
require "elastic_graph/support/hash_util"
require "yaml"

module ElasticGraph
  module HealthCheck
    RSpec.describe "HealthChecker", :uses_datastore, :factories, :builds_graphql do
      let(:now) { ::Time.iso8601("2022-02-14T12:30:00Z") }
      let(:graphql) { build_graphql(extension_settings: Support::HashUtil.stringify_keys(extension_settings), clock: class_double(::Time, now: now)) }
      let(:health_checker) { HealthChecker.build_from(graphql) }
      let(:extension_settings) do
        {
          health_check: {
            clusters_to_consider: ["main", "other2"],
            data_recency_checks: {
              Widget: {
                expected_max_recency_seconds: 300,
                timestamp_field: "created_at2" # use a field that has an alternate `name_in_index`.
              },
              Component: {
                expected_max_recency_seconds: 30,
                timestamp_field: "created_at"
              }
            }
          }
        }
      end

      it "returns health status", :expect_index_exclusions do
        index_into(
          graphql,
          widget = build(:widget, id: "w1", created_at: (now - 20).iso8601),
          component = build(:component, id: "c1", created_at: (now - 200).iso8601)
        )

        status = health_checker.check_health

        expect(status).to be_a HealthStatus
        expect(status.category).to eq(:degraded) # Component latest record is too old

        expect(status.cluster_health_by_name).to include("main", "other2")
        expect(status.cluster_health_by_name["main"]).to be_a(HealthStatus::ClusterHealth).and have_attributes(status: /(green|red|yellow)/)
        expect(status.cluster_health_by_name["other2"]).to be_a(HealthStatus::ClusterHealth).and have_attributes(status: /(green|red|yellow)/)

        expect(status.latest_record_by_type).to eq({
          "Widget" => HealthStatus::LatestRecord.new(
            id: widget.fetch(:id),
            timestamp: ::Time.iso8601(widget.fetch(:created_at)),
            seconds_newer_than_required: 280 # 300 - 20
          ),
          "Component" => HealthStatus::LatestRecord.new(
            id: component.fetch(:id),
            timestamp: ::Time.iso8601(component.fetch(:created_at)),
            seconds_newer_than_required: -170 # 30 - 200
          )
        })

        # Verify that our query was optimized to exclude the pre-2022 indices.
        expect(indices_excluded_from_searches("main").flatten).to contain_exactly(
          "widgets_rollover__before_2019",
          "widgets_rollover__2019",
          "widgets_rollover__2020",
          "widgets_rollover__2021"
        )
      end
    end
  end
end
