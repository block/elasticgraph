# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/warehouse_lambda/config"
require "yaml"

module ElasticGraph
  class WarehouseLambda
    RSpec.describe Config do
      it "parses s3_path_prefix and s3_bucket_name from YAML config" do
        config = Config.from_parsed_yaml("warehouse" => {
          "s3_path_prefix" => "CustomPrefix",
          "s3_bucket_name" => "my-bucket"
        })
        expect(config.s3_path_prefix).to eq "CustomPrefix"
        expect(config.s3_bucket_name).to eq "my-bucket"
      end

      it "raises an error when s3_path_prefix is nil" do
        expect {
          Config.from_parsed_yaml("warehouse" => {
            "s3_path_prefix" => nil,
            "s3_bucket_name" => "bucket"
          })
        }.to raise_error ::ElasticGraph::Errors::ConfigError, a_string_including("warehouse", "s3_path_prefix")
      end

      it "raises an error when s3_path_prefix is an empty string" do
        expect {
          Config.from_parsed_yaml("warehouse" => {
            "s3_path_prefix" => "",
            "s3_bucket_name" => "bucket"
          })
        }.to raise_error ::ElasticGraph::Errors::ConfigError, a_string_including("warehouse", "s3_path_prefix")
      end

      it "raises an error when s3_path_prefix is only whitespace" do
        expect {
          Config.from_parsed_yaml("warehouse" => {
            "s3_path_prefix" => "   ",
            "s3_bucket_name" => "bucket"
          })
        }.to raise_error ::ElasticGraph::Errors::ConfigError, a_string_including("warehouse", "s3_path_prefix")
      end

      it "raises an error when s3_bucket_name is missing" do
        expect {
          Config.from_parsed_yaml("warehouse" => {"s3_path_prefix" => "prefix"})
        }.to raise_error ::ElasticGraph::Errors::ConfigError, a_string_including("warehouse", "s3_bucket_name")
      end
    end
  end
end
