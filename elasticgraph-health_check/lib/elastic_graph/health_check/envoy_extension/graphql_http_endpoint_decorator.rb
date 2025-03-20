# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "delegate"
require "elastic_graph/graphql/http_endpoint"
require "uri"

module ElasticGraph
  module HealthCheck
    module EnvoyExtension
      # Intercepts HTTP requests so that a health check can be performed if it's a GET request to the configured health check path.
      # The HTTP response follows Envoy HTTP health check guidelines:
      #
      # https://www.envoyproxy.io/docs/envoy/latest/intro/arch_overview/upstream/health_checking
      class GraphQLHTTPEndpointDecorator < DelegateClass(GraphQL::HTTPEndpoint)
        def initialize(http_endpoint, health_check_http_path_segment:, health_checker:, logger:)
          super(http_endpoint)
          @health_check_http_path_segment = health_check_http_path_segment.delete_prefix("/").delete_suffix("/")
          @health_checker = health_checker
          @logger = logger
        end

        __skip__ =
          def process(request, **)
            if request.http_method == :get && URI(request.url).path.split("/").include?(@health_check_http_path_segment)
              perform_health_check
            else
              super
            end
          end

        private

        RESPONSES_BY_HEALTH_STATUS_CATEGORY = {
          healthy: [200, "Healthy!", {}],
          unhealthy: [500, "Unhealthy!", {}],
          # https://www.envoyproxy.io/docs/envoy/latest/intro/arch_overview/upstream/health_checking#degraded-health
          degraded: [200, "Degraded.", {"x-envoy-degraded" => "true"}]
        }

        def perform_health_check
          status = @health_checker.check_health
          @logger.info status.to_loggable_description

          status, message, headers = RESPONSES_BY_HEALTH_STATUS_CATEGORY.fetch(status.category)

          GraphQL::HTTPResponse.new(
            status_code: status,
            headers: headers.merge("Content-Type" => "text/plain"),
            body: message
          )
        end
      end
    end
  end
end
