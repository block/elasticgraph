# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/errors"
require "elastic_graph/health_check/envoy_extension/graphql_http_endpoint_decorator"
require "elastic_graph/health_check/health_checker"

module ElasticGraph
  module HealthCheck
    # An extension module that hooks into the HTTP endpoint to provide Envoy health checks.
    module EnvoyExtension
      def graphql_http_endpoint
        @graphql_http_endpoint ||=
          begin
            http_path_segment = config.extension_settings.dig("health_check", "http_path_segment")
            http_path_segment ||= runtime_metadata
              .graphql_extension_modules
              .find { |ext_mod| ext_mod.extension_class == EnvoyExtension }
              &.extension_config
              &.dig(:http_path_segment)

            if http_path_segment.nil?
              raise ElasticGraph::Errors::ConfigSettingNotSetError, "Health check `http_path_segment` is not configured. " \
                "Either set under `health_check` in YAML config or pass it along if you register the `EnvoyExtension` " \
                "via `register_graphql_extension`."
            end

            GraphQLHTTPEndpointDecorator.new(
              super,
              health_check_http_path_segment: http_path_segment,
              health_checker: HealthChecker.build_from(self),
              logger: logger
            )
          end
      end
    end
  end
end
