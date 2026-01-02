# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/support/config"

module ElasticGraph
  module HealthCheck
    class Config < Support::Config.define(:clusters_to_consider, :data_recency_checks, :healthy_ttl_seconds, :unhealthy_ttl_seconds)
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
          healthy_ttl_seconds: {
            description: "The number of seconds to cache a healthy health check result. When set, health check results " \
              "with a `healthy` category will be cached for this duration, reducing load on the datastore. " \
              "Set to 0 or omit to disable caching of healthy results.",
            type: "number",
            minimum: 0,
            default: 0, # : untyped
            examples: [0, 28, 60]
          },
          unhealthy_ttl_seconds: {
            description: "The number of seconds to cache an unhealthy or degraded health check result. When set, " \
              "health check results with an `unhealthy` or `degraded` category will be cached for this duration. " \
              "This is typically shorter than `healthy_ttl_seconds` to allow faster recovery detection. " \
              "Set to 0 or omit to disable caching of unhealthy results.",
            type: "number",
            minimum: 0,
            default: 0, # : untyped
            examples: [0, 1, 5]
          },
          http_path_segment: {
            description: "The HTTP path segment used to identify health check requests. When a GET request's URL " \
              "contains this segment as one of its path segments, it will be handled as a health check request " \
              "instead of a GraphQL query.",
            type: "string",
            minLength: 1,
            examples: ["health", "healthz", "healthcheck"]
          }
        }

      private

      # Note: http_path_segment is accepted but not stored in the Config since it's handled
      # separately by EnvoyExtension (which reads it directly from extension_settings).
      def convert_values(clusters_to_consider:, data_recency_checks:, healthy_ttl_seconds:, unhealthy_ttl_seconds:, http_path_segment: nil)
        {
          clusters_to_consider: clusters_to_consider,
          data_recency_checks: data_recency_checks.transform_values do |value_hash|
            DataRecencyCheck.new(
              expected_max_recency_seconds: value_hash.fetch("expected_max_recency_seconds"),
              timestamp_field: value_hash.fetch("timestamp_field")
            )
          end,
          healthy_ttl_seconds: healthy_ttl_seconds,
          unhealthy_ttl_seconds: unhealthy_ttl_seconds
        }
      end

      DataRecencyCheck = ::Data.define(:expected_max_recency_seconds, :timestamp_field)
    end
  end
end
