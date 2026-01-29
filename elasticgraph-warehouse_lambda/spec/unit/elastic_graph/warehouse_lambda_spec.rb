# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "aws-sdk-s3"
require "support/builds_warehouse_lambda"

module ElasticGraph
  RSpec.describe WarehouseLambda do
    include BuildsWarehouseLambda

    # Without these ENV vars, instantiating the S3 client causes it to try to fetch instance profile creds, which significantly
    # slows these tests down and produces warnings:
    # > Error retrieving instance profile credentials: Failed to open TCP connection to 169.254.169.254:80 (execution expired)
    around do |ex|
      with_env("AWS_ACCESS_KEY_ID" => "AWS_AKI", "AWS_SECRET_ACCESS_KEY" => "AWS_SAK", &ex)
    end

    it "returns non-nil values from each attribute" do
      expect_to_return_non_nil_values_from_all_attributes(build_warehouse_lambda)
    end

    describe ".from_parsed_yaml" do
      it "builds a WarehouseLambda instance from parsed YAML" do
        parsed_yaml = CommonSpecHelpers.parsed_test_settings_yaml.merge("warehouse" => {
          "s3_path_prefix" => "Data001",
          "s3_bucket_name" => "test-bucket",
          "aws_region" => "us-west-2"
        })

        warehouse_lambda = WarehouseLambda.from_parsed_yaml(parsed_yaml)

        expect(warehouse_lambda).to be_a WarehouseLambda
        expect(warehouse_lambda.indexer).to be_a Indexer
        expect(warehouse_lambda.warehouse_dumper).to be_a WarehouseLambda::WarehouseDumper
      end

      it "raises an error when warehouse config is missing" do
        expect {
          WarehouseLambda.from_parsed_yaml(CommonSpecHelpers.parsed_test_settings_yaml)
        }.to raise_error Errors::ConfigError, a_string_including("warehouse")
      end
    end

    describe "#indexer" do
      it "uses the `warehouse_dumper` as its `datastore_router`" do
        warehouse_lambda = build_warehouse_lambda

        expect(warehouse_lambda.indexer.datastore_router).to be warehouse_lambda.warehouse_dumper
      end
    end

    describe "#s3_client" do
      it "uses the provided `aws_region`" do
        warehouse_lambda = build_warehouse_lambda(aws_region: "ap-east-1")

        expect(warehouse_lambda.s3_client.config.region).to eq "ap-east-1"
      end

      it "falls back to AWS_REGION env var when `aws_region` is not configured" do
        with_env "AWS_REGION" => "ap-south-1" do
          warehouse_lambda = build_warehouse_lambda(aws_region: nil)

          expect(warehouse_lambda.s3_client.config.region).to eq "ap-south-1"
        end
      end

      it "raises an error if `aws_region` is not configured and `AWS_REGION` env var is not set" do
        # Clear all AWS region sources to ensure MissingRegionError is raised.
        # We must also reset `Aws.shared_config` since it caches parsed config from ~/.aws/config.
        with_env("AWS_REGION" => nil, "AWS_DEFAULT_REGION" => nil, "AWS_CONFIG_FILE" => "/nonexistent") do
          ::Aws.instance_variable_set(:@shared_config, nil)

          warehouse_lambda = build_warehouse_lambda(aws_region: nil)

          expect {
            warehouse_lambda.s3_client
          }.to raise_error ::Aws::Errors::MissingRegionError
        end
      end
    end
  end
end
