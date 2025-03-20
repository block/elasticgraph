# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/lambda_support/json_aware_lambda_log_formatter"
require "faraday_middleware/aws_sigv4"
require "json"

module ElasticGraph
  module LambdaSupport
    # Helper method for building ElasticGraph components from our lambda ENV vars.
    # `klass` is expected to be `ElasticGraph::Admin`, `ElasticGraph::GraphQL`, or `ElasticGraph::Indexer`.
    #
    # This is meant to only deal with ENV vars and config that are common across all ElasticGraph
    # components (e.g. logging and OpenSearch clients). ENV vars that are specific to one component
    # should be handled elsewhere. This accepts a block which can further customize configuration as
    # needed.
    def self.build_from_env(klass)
      klass.from_yaml_file(
        ENV.fetch("ELASTICGRAPH_YAML_CONFIG"),
        datastore_client_customization_block: ->(faraday) { configure_datastore_client(faraday) }
      ) do |settings|
        settings = settings.merge(
          "logger" => override_logger_config(settings.fetch("logger")),
          "datastore" => override_datastore_config(settings.fetch("datastore"))
        )

        settings = yield(settings) if block_given?
        settings
      end
    end

    private

    def self.override_datastore_config(datastore_config)
      env_urls_by_cluster = ::JSON.parse(ENV.fetch("OPENSEARCH_CLUSTER_URLS"))
      file_settings_by_cluster = datastore_config.fetch("clusters").transform_values { |v| v["settings"] }

      datastore_config.merge(
        "clusters" => env_urls_by_cluster.to_h do |cluster_name, url|
          cluster_def = {
            "url" => url,
            "backend" => "opensearch",
            "settings" => file_settings_by_cluster[cluster_name] || {}
          }

          [cluster_name, cluster_def]
        end
      )
    end

    def self.override_logger_config(logger_config)
      logger_config.merge({
        "level" => ENV["ELASTICGRAPH_LOG_LEVEL"],
        "formatter" => JSONAwareLambdaLogFormatter.name
      }.compact)
    end

    def self.configure_datastore_client(faraday)
      faraday.request :aws_sigv4,
        service: "es",
        region: ENV.fetch("AWS_REGION"), # assumes the lambda and OpenSearch cluster live in the same region.
        access_key_id: ENV.fetch("AWS_ACCESS_KEY_ID"),
        secret_access_key: ENV.fetch("AWS_SECRET_ACCESS_KEY"),
        session_token: ENV["AWS_SESSION_TOKEN"] # optional
    end

    private_class_method :override_datastore_config, :override_logger_config, :configure_datastore_client
  end
end
