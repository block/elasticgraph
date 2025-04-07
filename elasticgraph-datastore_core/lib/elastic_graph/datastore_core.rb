# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/datastore_core/config"
require "elastic_graph/schema_artifacts/from_disk"
require "elastic_graph/support/logger"

module ElasticGraph
  # The entry point into this library. Create an instance of this class to get access to
  # the public interfaces provided by this library.
  class DatastoreCore
    # @dynamic config, schema_artifacts, logger, client_customization_block
    attr_reader :config, :schema_artifacts, :logger, :client_customization_block

    def self.from_parsed_yaml(parsed_yaml, &client_customization_block)
      new(
        config: DatastoreCore::Config.from_parsed_yaml(parsed_yaml),
        logger: Support::Logger.from_parsed_yaml(parsed_yaml),
        schema_artifacts: SchemaArtifacts.from_parsed_yaml(parsed_yaml),
        client_customization_block: client_customization_block
      )
    end

    def initialize(
      config:,
      logger:,
      schema_artifacts:,
      clients_by_name: nil,
      client_customization_block: nil
    )
      @config = config
      @logger = logger
      @schema_artifacts = schema_artifacts
      @clients_by_name = clients_by_name
      @client_customization_block = client_customization_block
    end

    # Exposes the datastore index definitions as a map, keyed by index definition name.
    def index_definitions_by_name
      @index_definitions_by_name ||= begin
        require "elastic_graph/datastore_core/index_definition"
        schema_artifacts.runtime_metadata.index_definitions_by_name.to_h do |name, index_def_metadata|
          index_def = IndexDefinition.with(
            name: name,
            runtime_metadata: index_def_metadata,
            config: config,
            datastore_clients_by_name: clients_by_name,
            schema_artifacts: schema_artifacts
          )

          [name, index_def]
        end
      end
    end

    # Exposes the datastore index definitions as a map, keyed by GraphQL type.
    # Note: the GraphQL type name is also used in non-GraphQL contexts (e.g. it is
    # used in events processed by elasticgraph-indexer), so we expose this hear instead
    # of from elasticgraph-graphql.
    def index_definitions_by_graphql_type
      @index_definitions_by_graphql_type ||= schema_artifacts
        .runtime_metadata
        .object_types_by_name
        .transform_values do |metadata|
          metadata.index_definition_names.map do |name|
            index_definitions_by_name.fetch(name)
          end
        end
    end

    # Exposes the datastore clients in a map, keyed by cluster name.
    def clients_by_name
      @clients_by_name ||= begin
        if (adapter_lib = config.client_faraday_adapter&.require)
          require adapter_lib
        end

        adapter_name = config.client_faraday_adapter&.name
        client_logger = config.log_traffic ? logger : nil

        config.clusters.to_h do |name, cluster_def|
          client = cluster_def.backend_client_class.new(
            name,
            faraday_adapter: adapter_name,
            url: cluster_def.url,
            logger: client_logger,
            retry_on_failure: config.max_client_retries,
            &@client_customization_block
          )

          [name, client]
        end
      end
    end
  end
end
