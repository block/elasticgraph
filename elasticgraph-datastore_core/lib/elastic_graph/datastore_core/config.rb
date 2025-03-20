# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/datastore_core/configuration/client_faraday_adapter"
require "elastic_graph/datastore_core/configuration/cluster_definition"
require "elastic_graph/datastore_core/configuration/index_definition"
require "elastic_graph/errors"

module ElasticGraph
  class DatastoreCore
    # Defines the configuration related to datastores.
    class Config < ::Data.define(
      # Configuration of the faraday adapter to use with the datastore client.
      :client_faraday_adapter,
      # Map of datastore cluster definitions, keyed by cluster name. The names will be referenced within
      # `index_definitions` by `query_cluster` and `index_into_clusters` to identify
      # datastore clusters. Each definition has a `url` and `settings`. `settings` contains datastore
      # settings in the flattened name form, e.g. `"cluster.max_shards_per_node": 2000`.
      :clusters,
      # Map of index definition names to `IndexDefinition` objects containing customizations
      # for the named index definitions for this environment.
      :index_definitions,
      # Determines if we log requests/responses to/from the datastore.
      # Defaults to `false`.
      :log_traffic,
      # Passed down to the datastore client, controls the number of times ElasticGraph attempts a call against
      # the datastore before failing. Retrying a handful of times is generally advantageous, since some sporadic
      # failures are expected during the course of operation, and better to retry than fail the entire call.
      # Defaults to 3.
      :max_client_retries
    )
      # Helper method to build an instance from parsed YAML config.
      def self.from_parsed_yaml(parsed_yaml)
        parsed_yaml = parsed_yaml.fetch("datastore")
        extra_keys = parsed_yaml.keys - EXPECTED_KEYS

        unless extra_keys.empty?
          raise Errors::ConfigError, "Unknown `datastore` config settings: #{extra_keys.join(", ")}"
        end

        new(
          client_faraday_adapter: Configuration::ClientFaradayAdapter.from_parsed_yaml(parsed_yaml),
          clusters: Configuration::ClusterDefinition.definitions_by_name_hash_from(parsed_yaml.fetch("clusters")),
          index_definitions: Configuration::IndexDefinition.definitions_by_name_hash_from(parsed_yaml.fetch("index_definitions")),
          log_traffic: parsed_yaml.fetch("log_traffic", false),
          max_client_retries: parsed_yaml.fetch("max_client_retries", 3)
        )
      end

      EXPECTED_KEYS = members.map(&:to_s)
    end
  end
end
