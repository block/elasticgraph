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
require "elastic_graph/warehouse_lambda/indexer_extension"
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

    attr_reader :logger, :indexer, :clock

    # Builds an `ElasticGraph::WarehouseLambda` instance from our lambda ENV vars.
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
      indexer.warehouse_lambda = self
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
        require "elastic_graph/warehouse_lambda/warehouse_dumper"
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
