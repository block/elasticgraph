# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/health_check/envoy_extension"

module ElasticGraph
  module HealthCheck
    RSpec.describe EnvoyExtension, :builds_graphql, :capture_logs do
      shared_examples_for "a health check endpoint" do
        let(:processed_graphql_queries) { [] }
        let(:health_status_log_line) { "HealthStatus: " }

        context "on a GET request to the health check HTTP path" do
          let(:degraded_header) { "x-envoy-degraded" }

          it "checks health and returns a 200 if healthy" do
            response = process(:get, "/health", with_configured_path_segment: "/health", cluster_status: "green")

            expect(response.status_code).to eq 200
            expect(response.body).to eq "Healthy!"
            expect(response.headers.keys).to exclude(degraded_header)

            expect(processed_graphql_queries).to be_empty
            expect(logged_output).to include(health_status_log_line)
          end

          it "checks health and returns a 500 if unhealthy" do
            response = process(:get, "/health", with_configured_path_segment: "/health", cluster_status: "red")

            expect(response.status_code).to eq 500
            expect(response.body).to eq "Unhealthy!"
            expect(response.headers.keys).to exclude(degraded_header)

            expect(processed_graphql_queries).to be_empty
            expect(logged_output).to include(health_status_log_line)
          end

          it "checks health and returns a 200 with the degraded header if degraded" do
            response = process(:get, "/health", with_configured_path_segment: "/health", cluster_status: "yellow")

            expect(response.status_code).to eq 200
            expect(response.body).to eq "Degraded."
            expect(response.headers).to include(degraded_header => "true")

            expect(processed_graphql_queries).to be_empty
            expect(logged_output).to include(health_status_log_line)
          end
        end

        it "processes the request as GraphQL for a non-GET request to the health check path" do
          response = process(:post, "/health", body: "query { __typename }", with_configured_path_segment: "/health")

          expect(response.body).to eq %({"data":{}})
          expect(processed_graphql_queries).to contain_exactly("query { __typename }")
          expect(logged_output).to exclude(health_status_log_line)
        end

        it "processes the request as GraphQL for a GET request to a path that contains the specified segment within a larger segment" do
          response = process(:get, "/foo/health_foo?#{URI.encode_www_form("query" => "query { __typename }")}", with_configured_path_segment: "/health")

          expect(response.body).to eq %({"data":{}})
          expect(processed_graphql_queries).to contain_exactly("query { __typename }")
          expect(logged_output).to exclude(health_status_log_line)
        end

        it "processes the request as a health check for a GET request to a path that has the configured segment as one of its segments" do
          response = process(:get, "/foo/health/bar?#{URI.encode_www_form("query" => "query { __typename }")}", with_configured_path_segment: "/health")

          expect(response.status_code).to eq 200
          expect(response.body).to eq "Healthy!"

          expect(processed_graphql_queries).to be_empty
          expect(logged_output).to include(health_status_log_line)
        end

        it "ignores a trailing `/` when determining if a path segment matches" do
          response = process(:get, "/foo/health/bar?#{URI.encode_www_form("query" => "query { __typename }")}", with_configured_path_segment: "health/")

          expect(response.status_code).to eq 200
          expect(response.body).to eq "Healthy!"

          expect(processed_graphql_queries).to be_empty
          expect(logged_output).to include(health_status_log_line)
        end

        it "raises an error if the `http_path_segment` is not configured" do
          expect {
            process(:get, "/health", with_configured_path_segment: nil)
          }.to raise_error Errors::ConfigSettingNotSetError, a_string_including("Health check `http_path_segment` is not configured")
        end

        def process(http_method, url, with_configured_path_segment:, body: nil, cluster_status: nil)
          graphql = build_graphql_for_path(with_configured_path_segment)

          status = HealthCheck::HealthStatus.new(
            cluster_health_by_name: {
              "main" => HealthCheck::HealthStatus::ClusterHealth.new(
                cluster_name: "my_cluster",
                status: cluster_status,
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
            },
            latest_record_by_type: {}
          )

          health_checker = instance_double(HealthCheck::HealthChecker, check_health: status)
          allow(HealthCheck::HealthChecker).to receive(:build_from).with(graphql).and_return(health_checker)

          allow(graphql.graphql_query_executor).to receive(:execute) do |query_string, **options|
            processed_graphql_queries << query_string
            {"data" => {}}
          end

          request = GraphQL::HTTPRequest.new(
            http_method: http_method,
            url: url,
            headers: {"Content-Type" => "application/graphql"},
            body: body
          )

          graphql.graphql_http_endpoint.process(request)
        end
      end

      context "when enabled via `register_graphql_extension`" do
        include_context "a health check endpoint"

        def build_graphql_for_path(http_path_segment)
          config = {http_path_segment: http_path_segment}.compact
          schema_artifacts = generate_schema_artifacts do |schema|
            schema.register_graphql_extension(EnvoyExtension, defined_at: "elastic_graph/health_check/envoy_extension", **config)
            schema.object_type "Widget" do |t|
              t.field "id", "ID"
              t.index "widgets"
            end
          end

          build_graphql(schema_artifacts: schema_artifacts)
        end
      end

      context "when enabled via YAML config" do
        include_context "a health check endpoint"

        def build_graphql_for_path(http_path_segment)
          build_graphql(extension_modules: [EnvoyExtension], extension_settings: {"health_check" => {
            "clusters_to_consider" => [],
            "data_recency_checks" => {},
            "http_path_segment" => http_path_segment
          }.compact})
        end
      end
    end
  end
end
