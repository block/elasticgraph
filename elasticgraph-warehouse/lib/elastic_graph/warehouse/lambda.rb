# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/indexer"
require "elastic_graph/lambda_support"
require "elastic_graph/support/from_yaml_file"
require "elastic_graph/warehouse/lambda/indexer_extension"
require "elastic_graph/warehouse/lambda/config"

module ElasticGraph
  module Warehouse
    # AWS Lambda adapter for dumping ElasticGraph-shaped JSONL files to S3.
    #
    # This class adapts ElasticGraph's indexing pipeline so that, instead of writing to the datastore,
    # it writes batched, gzipped JSON Lines (JSONL) files to Amazon S3. Each line in the file
    # conforms to your ElasticGraph schema's latest JSON Schema for the corresponding object type.
    #
    # @example Using the warehouse lambda in AWS Lambda
    #   require "elastic_graph/warehouse/lambda/lambda_function"
    #   # The ElasticGraphWarehouse constant is defined automatically
    class Lambda
      extend ::ElasticGraph::Support::FromYamlFile

      # @dynamic logger, indexer, clock
      attr_reader :logger, :indexer, :clock

      # Builds an `ElasticGraph::Warehouse::Lambda` instance from lambda ENV vars.
      def self.from_env
        ::ElasticGraph::LambdaSupport.build_from_env(self)
      end

      def self.from_parsed_yaml(parsed_yaml)
        new(
          config: Config.from_parsed_yaml(parsed_yaml),
          indexer: ::ElasticGraph::Indexer.from_parsed_yaml(parsed_yaml)
        )
      end

      def initialize(config:, indexer:, s3_client: nil, s3_bucket_name: nil, clock: ::Time)
        indexer.extend IndexerExtension
        # After extending with IndexerExtension, indexer has `warehouse_lambda=` method.
        # steep:ignore:start
        indexer.warehouse_lambda = self
        # steep:ignore:end
        @logger = indexer.logger
        @indexer = indexer
        @s3_client = s3_client
        @s3_bucket_name = s3_bucket_name
        @config = config
        @clock = clock
      end

      def processor
        indexer.processor
      end

      def warehouse_dumper
        @warehouse_dumper ||= begin
          require "elastic_graph/warehouse/lambda/warehouse_dumper"
          WarehouseDumper.new(
            logger: logger,
            s3_client: s3_client,
            s3_bucket_name: s3_bucket_name,
            s3_file_prefix: @config.s3_path_prefix,
            latest_json_schema_version: indexer.schema_artifacts.latest_json_schema_version,
            clock: clock
          )
        end
      end

      def s3_client
        @s3_client ||= begin
          require "aws-sdk-s3"
          ::Aws::S3::Client.new
        end
      end

      def s3_bucket_name
        @s3_bucket_name ||= ENV.fetch("DATAWAREHOUSE_S3_BUCKET_NAME")
      end
    end
  end
end
