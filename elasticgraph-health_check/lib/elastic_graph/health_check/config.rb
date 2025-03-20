# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  module HealthCheck
    class Config < ::Data.define(
      # The list of clusters to perform datastore status health checks on. A `green` status maps to `healthy`, a
      # `yellow` status maps to `degraded`, and a `red` status maps to `unhealthy`. The returned status is the minimum
      # status from all clusters in the list (a `yellow` cluster and a `green` cluster will result in a `degraded` status).
      #
      # Example: ["cluster-one", "cluster-two"]
      :clusters_to_consider,
      # A map of types to perform recency checks on. If no new records for that type have been indexed within the specified
      # period, a `degraded` status will be returned.
      #
      # Example: { Widget: { timestamp_field: createdAt, expected_max_recency_seconds: 30 }}
      :data_recency_checks
    )
      EMPTY = new([], {})

      def self.from_parsed_yaml(config_hash)
        config_hash = config_hash.fetch("health_check") { return EMPTY }

        new(
          clusters_to_consider: config_hash.fetch("clusters_to_consider"),
          data_recency_checks: config_hash.fetch("data_recency_checks").transform_values do |value_hash|
            DataRecencyCheck.from(value_hash)
          end
        )
      end

      DataRecencyCheck = ::Data.define(:expected_max_recency_seconds, :timestamp_field) do
        # @implements DataRecencyCheck
        def self.from(config_hash)
          new(
            expected_max_recency_seconds: config_hash.fetch("expected_max_recency_seconds"),
            timestamp_field: config_hash.fetch("timestamp_field")
          )
        end
      end
    end
  end
end
