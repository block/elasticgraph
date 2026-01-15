# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/warehouse_lambda"

module ElasticGraph
  RSpec.describe WarehouseLambda do
    it "can be initialized from parsed YAML" do
      warehouse_lambda = WarehouseLambda.from_parsed_yaml(CommonSpecHelpers.parsed_test_settings_yaml.merge({
        "warehouse" => {"s3_path_prefix" => "Data001"}
      }))

      expect(warehouse_lambda).to be_a(WarehouseLambda)
      expect(warehouse_lambda.indexer).to be_a(Indexer)
      expect(warehouse_lambda.logger).to be_a(::Logger)
    end

    it "extends the indexer with IndexerExtension on initialization" do
      indexer = Indexer.from_parsed_yaml(CommonSpecHelpers.parsed_test_settings_yaml)
      config = WarehouseLambda::Config.new(s3_path_prefix: "Data001")

      warehouse_lambda = WarehouseLambda.new(config: config, indexer: indexer)

      expect(indexer).to be_a_kind_of(WarehouseLambda::IndexerExtension)
      expect(indexer.warehouse_lambda).to eq warehouse_lambda
    end

    it "exposes the indexer's processor" do
      indexer = Indexer.from_parsed_yaml(CommonSpecHelpers.parsed_test_settings_yaml)
      config = WarehouseLambda::Config.new(s3_path_prefix: "Data001")
      s3_client = ::Aws::S3::Client.new(stub_responses: true)

      warehouse_lambda = WarehouseLambda.new(
        config: config,
        indexer: indexer,
        s3_client: s3_client,
        s3_bucket_name: "test-bucket"
      )

      expect(warehouse_lambda.processor).to eq warehouse_lambda.indexer.processor
    end

    it "lazily initializes s3_client when not provided" do
      indexer = Indexer.from_parsed_yaml(CommonSpecHelpers.parsed_test_settings_yaml)
      config = WarehouseLambda::Config.new(s3_path_prefix: "Data001")

      with_env({"AWS_REGION" => "us-west-2"}) do
        warehouse_lambda = WarehouseLambda.new(config: config, indexer: indexer, s3_bucket_name: "test-bucket")

        expect(warehouse_lambda.s3_client).to be_a(::Aws::S3::Client)
      end
    end

    it "uses provided s3_client when given" do
      indexer = Indexer.from_parsed_yaml(CommonSpecHelpers.parsed_test_settings_yaml)
      config = WarehouseLambda::Config.new(s3_path_prefix: "Data001")
      custom_client = ::Aws::S3::Client.new(stub_responses: true)

      warehouse_lambda = WarehouseLambda.new(
        config: config,
        indexer: indexer,
        s3_client: custom_client,
        s3_bucket_name: "test-bucket"
      )

      expect(warehouse_lambda.s3_client).to eq custom_client
    end

    it "reads s3_bucket_name from ENV when not provided" do
      indexer = Indexer.from_parsed_yaml(CommonSpecHelpers.parsed_test_settings_yaml)
      config = WarehouseLambda::Config.new(s3_path_prefix: "Data001")

      warehouse_lambda = WarehouseLambda.new(config: config, indexer: indexer)

      # Stub the ENV lookup
      stub_const("ENV", {"DATAWAREHOUSE_S3_BUCKET_NAME" => "env-bucket"})

      expect(warehouse_lambda.s3_bucket_name).to eq "env-bucket"
    end

    it "uses provided s3_bucket_name when given" do
      indexer = Indexer.from_parsed_yaml(CommonSpecHelpers.parsed_test_settings_yaml)
      config = WarehouseLambda::Config.new(s3_path_prefix: "Data001")

      warehouse_lambda = WarehouseLambda.new(
        config: config,
        indexer: indexer,
        s3_bucket_name: "custom-bucket"
      )

      expect(warehouse_lambda.s3_bucket_name).to eq "custom-bucket"
    end

    it "lazily initializes warehouse_dumper" do
      indexer = Indexer.from_parsed_yaml(CommonSpecHelpers.parsed_test_settings_yaml)
      config = WarehouseLambda::Config.new(s3_path_prefix: "Data001")
      s3_client = ::Aws::S3::Client.new(stub_responses: true)

      warehouse_lambda = WarehouseLambda.new(
        config: config,
        indexer: indexer,
        s3_client: s3_client,
        s3_bucket_name: "test-bucket"
      )

      dumper = warehouse_lambda.warehouse_dumper

      expect(dumper).to be_a(WarehouseLambda::WarehouseDumper)
      # Should return the same instance on subsequent calls
      expect(warehouse_lambda.warehouse_dumper).to equal(dumper)
    end

    it "uses custom clock when provided" do
      indexer = Indexer.from_parsed_yaml(CommonSpecHelpers.parsed_test_settings_yaml)
      config = WarehouseLambda::Config.new(s3_path_prefix: "Data001")
      custom_clock = class_double(::Time, now: ::Time.utc(2025, 1, 1))

      warehouse_lambda = WarehouseLambda.new(
        config: config,
        indexer: indexer,
        s3_bucket_name: "test-bucket",
        clock: custom_clock
      )

      expect(warehouse_lambda.clock).to eq custom_clock
    end
  end
end
