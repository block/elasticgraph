# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/support/config"

module ElasticGraph
  module HealthCheck
    class Config < Support::Config.define(:clusters_to_consider, :data_recency_checks, :timeout_ms)
      json_schema at: "health_check",
        optional: true,
        description: "Configuration for health checks used by `elasticgraph-health_check`.",
        properties: {
          clusters_to_consider: {
            description: "The list of clusters to perform datastore status health checks on. A `green` status maps to `healthy`, a " \
              "`yellow` status maps to `degraded`, and a `red` status maps to `unhealthy`. The returned status is the minimum " \
              "status from all clusters in the list (a `yellow` cluster and a `green` cluster will result in a `degraded` status).",
            type: "array",
            items: {type: "string", minLength: 1},
            default: [], # : untyped
            examples: [
              [], # : untyped
              ["cluster-one", "cluster-two"]
            ]
          },
          data_recency_checks: {
            description: "A map of types to perform recency checks on. If no new records for that type have been indexed within the specified " \
              "period, a `degraded` status will be returned.",
            type: "object",
            patternProperties: {/^[A-Z]\w*$/.source => {
              type: "object",
              description: "Configuration for data recency checks on a specific type.",
              examples: [{"timestamp_field" => "createdAt", "expected_max_recency_seconds" => 30}],
              properties: {
                expected_max_recency_seconds: {
                  type: "integer",
                  minimum: 0,
                  description: "The maximum number of seconds since the last record was indexed for this type before considering it stale.",
                  examples: [30, 300, 3600]
                },
                timestamp_field: {
                  type: "string",
                  minLength: 1,
                  description: "The name of the timestamp field to use for recency checks.",
                  examples: ["createdAt", "updatedAt"]
                }
              },
              required: ["expected_max_recency_seconds", "timestamp_field"]
            }},
            default: {}, # : untyped
            examples: [
              {}, # : untyped
              {"Widget" => {"timestamp_field" => "createdAt", "expected_max_recency_seconds" => 30}}
            ]
          },
          timeout_ms: {
            description: "The timeout in milliseconds for health check datastore queries. If the queries take longer than this, " \
              "the health check will fail with a timeout error. This prevents slow or unresponsive datastores from causing " \
              "the health check endpoint to hang.",
            type: "integer",
            minimum: 1,
            default: 5000,
            examples: [1000, 5000, 10000]
          }
        }

      private

      def convert_values(clusters_to_consider:, data_recency_checks:, timeout_ms:)
        {
          clusters_to_consider: clusters_to_consider,
          data_recency_checks: data_recency_checks.transform_values do |value_hash|
            DataRecencyCheck.new(
              expected_max_recency_seconds: value_hash.fetch("expected_max_recency_seconds"),
              timestamp_field: value_hash.fetch("timestamp_field")
            )
          end,
          timeout_ms: timeout_ms
        }
      end

      DataRecencyCheck = ::Data.define(:expected_max_recency_seconds, :timestamp_field)
    end
  end
end
