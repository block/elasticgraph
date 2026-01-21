# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/datastore_core"
require "elastic_graph/indexer/config"
require "elastic_graph/lambda_support"
require "elastic_graph/support/from_yaml_file"
require "elastic_graph/warehouse_lambda/config"

module ElasticGraph
  # Wraps an {Indexer} to dump data to S3 instead of indexing to a datastore.
  # This is a stateful wrapper class (unlike {IndexerLambda} and {GraphQLLambda},
  # which are namespace modules), as it manages the relationship between the
  # indexer, S3 client, and warehouse dumper.
  #
  # @private
  class WarehouseLambda
    extend Support::FromYamlFile

    # Builds an `ElasticGraph::WarehouseLambda` instance from our lambda ENV vars.
    def self.warehouse_lambda_from_env
      LambdaSupport.build_from_env(WarehouseLambda)
    end

    # @return [Config] warehouse configuration
    # @return [Indexer::Config] indexer configuration
    # @return [DatastoreCore] datastore core for accessing schema artifacts
    # @return [Logger] logger instance from datastore core
    # @return [Module] clock module for time generation
    # @dynamic config, indexer_config, datastore_core, logger, clock, indexer
    attr_reader :config, :indexer_config, :datastore_core, :logger, :clock

    # Builds an `ElasticGraph::WarehouseLambda` instance from parsed YAML configuration.
    #
    # @param parsed_yaml [Hash] parsed YAML configuration
    # @yield [Datastore::Client] optional block to customize the datastore client
    # @return [WarehouseLambda] configured warehouse lambda instance
    def self.from_parsed_yaml(parsed_yaml, &datastore_client_customization_block)
      new(
        config: Config.from_parsed_yaml!(parsed_yaml),
        indexer_config: Indexer::Config.from_parsed_yaml(parsed_yaml) || Indexer::Config.new,
        datastore_core: DatastoreCore.from_parsed_yaml(parsed_yaml, &datastore_client_customization_block)
      )
    end

    # Initializes a WarehouseLambda instance.
    #
    # @param config [Config] warehouse configuration
    # @param indexer_config [Config] indexer configuration
    # @param datastore_core [DatastoreCore] datastore core for accessing schema artifacts
    # @param clock [Module] clock module for time generation (defaults to {::Time})
    # @param s3_client [Aws::S3::Client, nil] optional S3 client (for testing)
    def initialize(config:, indexer_config:, datastore_core:, clock: ::Time, s3_client: nil)
      @config = config
      @indexer_config = indexer_config
      @datastore_core = datastore_core
      @logger = datastore_core.logger
      @clock = clock
      @s3_client = s3_client
    end

    # Returns the processor from the indexer for event processing.
    #
    # @return [Processor] the processor that handles incoming events
    def processor
      indexer.processor
    end

    # Returns the indexer instance, lazily building it on first access.
    #
    # @return [Indexer] the indexer that processes events
    def indexer
      @indexer ||= begin
        require "elastic_graph/indexer"
        Indexer.new(
          config: indexer_config,
          datastore_core: datastore_core,
          datastore_router: warehouse_dumper,
          clock: clock
        )
      end
    end

    # Returns the warehouse dumper instance, lazily building it on first access.
    #
    # @return [WarehouseDumper] the dumper that writes data to S3
    def warehouse_dumper
      @warehouse_dumper ||= begin
        require "elastic_graph/warehouse_lambda/warehouse_dumper"
        WarehouseDumper.new(
          logger: logger,
          s3_client: s3_client,
          s3_bucket_name: config.s3_bucket_name,
          s3_file_prefix: config.s3_path_prefix,
          clock: clock
        )
      end
    end

    # Returns the S3 client instance, lazily building it on first access.
    #
    # @return [Aws::S3::Client] the S3 client for uploading data
    def s3_client
      @s3_client ||= begin
        require "aws-sdk-s3"

        if (region = config.aws_region)
          ::Aws::S3::Client.new(region: region)
        else
          ::Aws::S3::Client.new
        end
      end
    end
  end
end
