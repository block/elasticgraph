# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/indexer"
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
    extend ::ElasticGraph::Support::FromYamlFile

    # @dynamic logger, indexer, clock, warehouse_dumper

    # @return [Logger] logger for recording diagnostic information
    # @return [Indexer] indexer instance that processes events
    # @return [WarehouseDumper] dumper that writes data to S3
    # @return [Module] clock module used for time generation (typically {::Time})
    attr_reader :logger, :indexer, :warehouse_dumper, :clock

    # Builds an `ElasticGraph::WarehouseLambda` instance from our lambda ENV vars.
    def self.from_env
      # :nocov: covered by lambda_function_spec in commit 3
      ::ElasticGraph::LambdaSupport.build_from_env(self)
      # :nocov:
    end

    # Builds an `ElasticGraph::WarehouseLambda` instance from parsed YAML configuration.
    #
    # @param parsed_yaml [Hash] parsed YAML configuration
    # @yield [Datastore::Client] optional block to customize the datastore client
    # @return [WarehouseLambda] configured warehouse lambda instance
    def self.from_parsed_yaml(parsed_yaml, &datastore_client_customization_block)
      config = Config.from_parsed_yaml!(parsed_yaml)

      # Build datastore_core first so we can access schema_artifacts
      datastore_core = ::ElasticGraph::DatastoreCore.from_parsed_yaml(parsed_yaml, &datastore_client_customization_block)

      # Create warehouse dumper with schema_artifacts from datastore_core
      warehouse_dumper = build_warehouse_dumper(
        config: config,
        logger: datastore_core.logger,
        latest_json_schema_version: datastore_core.schema_artifacts.latest_json_schema_version
      )

      # Create indexer with warehouse_dumper as the datastore_router
      indexer = ::ElasticGraph::Indexer.new(
        config: ::ElasticGraph::Indexer::Config.from_parsed_yaml(parsed_yaml) || ::ElasticGraph::Indexer::Config.new,
        datastore_core: datastore_core,
        datastore_router: warehouse_dumper
      )

      new(
        indexer: indexer,
        warehouse_dumper: warehouse_dumper,
        clock: ::Time
      )
    end

    def initialize(indexer:, warehouse_dumper:, clock: ::Time)
      @logger = indexer.logger
      @indexer = indexer
      @warehouse_dumper = warehouse_dumper
      @clock = clock
    end

    # Returns the processor from the indexer for event processing.
    #
    # @return [Processor] the processor that handles incoming events
    def processor
      indexer.processor
    end

    private_class_method def self.build_warehouse_dumper(config:, logger:, latest_json_schema_version:)
      require "elastic_graph/warehouse_lambda/warehouse_dumper"
      require "aws-sdk-s3"

      s3_client_options = {} #: ::Hash[::Symbol, ::String]
      if (region = config.aws_region)
        s3_client_options[:region] = region
      end
      s3_client = ::Aws::S3::Client.new(**s3_client_options)

      WarehouseDumper.new(
        logger: logger,
        s3_client: s3_client,
        s3_bucket_name: config.s3_bucket_name,
        s3_file_prefix: config.s3_path_prefix,
        latest_json_schema_version: latest_json_schema_version,
        clock: ::Time
      )
    end
  end
end
