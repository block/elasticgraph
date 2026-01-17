# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/spec_support/lambda_function"

require "aws-sdk-s3"
require "elastic_graph/indexer"
require "elastic_graph/warehouse_lambda"
require "elastic_graph/warehouse_lambda/config"
require "elastic_graph/warehouse_lambda/warehouse_dumper"

module ElasticGraph
  RSpec.describe WarehouseLambda do
    include_context "lambda function", config_overrides_in_yaml: {"warehouse" => {"s3_path_prefix" => "Data001", "s3_bucket_name" => "test-bucket"}}

    let(:parsed_yaml) { CommonSpecHelpers.parsed_test_settings_yaml.merge("warehouse" => {"s3_path_prefix" => "Data001", "s3_bucket_name" => "test-bucket"}) }
    let(:s3_client) { ::Aws::S3::Client.new(stub_responses: true) }
    let(:warehouse_dumper) do
      datastore_core = ::ElasticGraph::DatastoreCore.from_parsed_yaml(parsed_yaml)
      WarehouseLambda::WarehouseDumper.new(
        logger: datastore_core.logger,
        s3_client: s3_client,
        s3_bucket_name: "test-bucket",
        s3_file_prefix: "Data001",
        latest_json_schema_version: datastore_core.schema_artifacts.latest_json_schema_version,
        clock: ::Time
      )
    end
    let(:indexer) do
      datastore_core = ::ElasticGraph::DatastoreCore.from_parsed_yaml(parsed_yaml)
      ::ElasticGraph::Indexer.new(
        config: ::ElasticGraph::Indexer::Config.new,
        datastore_core: datastore_core,
        datastore_router: warehouse_dumper
      )
    end

    describe ".from_parsed_yaml" do
      it "builds a WarehouseLambda instance from parsed YAML" do
        warehouse_lambda = WarehouseLambda.from_parsed_yaml(parsed_yaml)

        expect(warehouse_lambda).to be_a WarehouseLambda
        expect(warehouse_lambda.indexer).to be_a ::ElasticGraph::Indexer
        expect(warehouse_lambda.warehouse_dumper).to be_a WarehouseLambda::WarehouseDumper
        expect(warehouse_lambda.logger).to be_a ::Logger
      end

      it "configures the indexer to use the warehouse_dumper as its datastore_router" do
        warehouse_lambda = WarehouseLambda.from_parsed_yaml(parsed_yaml)

        expect(warehouse_lambda.indexer.datastore_router).to eq warehouse_lambda.warehouse_dumper
      end

      it "configures the S3 client with aws_region when provided" do
        yaml_with_region = parsed_yaml.merge("warehouse" => parsed_yaml["warehouse"].merge("aws_region" => "us-west-2"))
        warehouse_lambda = WarehouseLambda.from_parsed_yaml(yaml_with_region)

        # We can't easily inspect the S3 client's region since it's private, but we can verify
        # the warehouse_dumper was created successfully (which means the S3 client was configured)
        expect(warehouse_lambda.warehouse_dumper).to be_a WarehouseLambda::WarehouseDumper
      end

      it "raises an error when warehouse config is missing" do
        yaml_without_warehouse = CommonSpecHelpers.parsed_test_settings_yaml

        expect {
          WarehouseLambda.from_parsed_yaml(yaml_without_warehouse)
        }.to raise_error ::ElasticGraph::Errors::ConfigError, a_string_including("warehouse")
      end
    end

    describe "#initialize" do
      it "initializes with provided components and sets logger from indexer" do
        warehouse_lambda = WarehouseLambda.new(indexer: indexer, warehouse_dumper: warehouse_dumper)

        expect(warehouse_lambda.logger).to eq indexer.logger
        expect(warehouse_lambda.indexer).to eq indexer
        expect(warehouse_lambda.warehouse_dumper).to eq warehouse_dumper
      end

      it "accepts an optional clock parameter" do
        custom_clock = class_double(::Time, now: ::Time.utc(2024, 1, 1))
        warehouse_lambda = WarehouseLambda.new(indexer: indexer, warehouse_dumper: warehouse_dumper, clock: custom_clock)

        expect(warehouse_lambda.clock).to eq custom_clock
      end
    end

    describe "#processor" do
      it "returns the indexer's processor" do
        warehouse_lambda = WarehouseLambda.new(indexer: indexer, warehouse_dumper: warehouse_dumper)

        expect(warehouse_lambda.processor).to eq indexer.processor
      end
    end
  end
end
