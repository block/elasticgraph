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
      it "raises an error when given an unrecognized config setting" do
        expect {
          Config.from_parsed_yaml("warehouse" => {
            "s3_path_prefix" => "PREFIX",
            "fake_setting" => 23
          })
        }.to raise_error ::ElasticGraph::Errors::ConfigError, a_string_including("fake_setting")
      end

      it "parses s3_path_prefix from YAML config" do
        config = Config.from_parsed_yaml("warehouse" => {"s3_path_prefix" => "CustomPrefix"})
        expect(config.s3_path_prefix).to eq "CustomPrefix"
      end

      it "returns nil when warehouse config is not specified" do
        config = Config.from_parsed_yaml({})
        expect(config).to be_nil
      end

      it "raises an error when s3_path_prefix is nil" do
        expect {
          Config.from_parsed_yaml("warehouse" => {"s3_path_prefix" => nil})
        }.to raise_error ::ElasticGraph::Errors::ConfigError, a_string_including("warehouse", "s3_path_prefix")
      end

      it "raises an error when s3_path_prefix is an empty string" do
        expect {
          Config.from_parsed_yaml("warehouse" => {"s3_path_prefix" => ""})
        }.to raise_error ::ElasticGraph::Errors::ConfigError, a_string_including("warehouse", "s3_path_prefix")
      end

      it "raises an error when s3_path_prefix is only whitespace" do
        expect {
          Config.from_parsed_yaml("warehouse" => {"s3_path_prefix" => "   "})
        }.to raise_error ::ElasticGraph::Errors::ConfigError, a_string_including("warehouse", "s3_path_prefix")
      end

      it "allows all expected config keys without error" do
        expect {
          Config.from_parsed_yaml("warehouse" => {
            "s3_path_prefix" => "Data999"
          })
        }.not_to raise_error
      end
    end
  end
end
