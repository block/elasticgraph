# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/warehouse/lambda/config"
require "yaml"

module ElasticGraph
  module Warehouse
    class Lambda
      RSpec.describe Config do
        it "raises an error when given an unrecognized config setting" do
          expect {
            Config.from_parsed_yaml("warehouse" => {
              "s3_path_prefix" => "PREFIX",
              "fake_setting" => 23
            })
          }.to raise_error ::ElasticGraph::Errors::ConfigError, a_string_including("fake_setting")
        end

        it "raises an error when s3_path_prefix is not specified" do
          expect {
            Config.from_parsed_yaml({})
          }.to raise_error ::ElasticGraph::Errors::ConfigSettingNotSetError, a_string_including("s3_path_prefix")
        end

        it "raises an error when s3_path_prefix is empty" do
          expect {
            Config.from_parsed_yaml("warehouse" => {"s3_path_prefix" => ""})
          }.to raise_error ::ElasticGraph::Errors::ConfigSettingNotSetError, a_string_including("s3_path_prefix")
        end

        it "raises an error when s3_path_prefix contains invalid characters" do
          expect {
            Config.from_parsed_yaml("warehouse" => {"s3_path_prefix" => "invalid/path"})
          }.to raise_error ::ElasticGraph::Errors::ConfigError, a_string_including("alphanumeric")
        end

        it "uses the provided s3_path_prefix when specified" do
          config = Config.from_parsed_yaml("warehouse" => {"s3_path_prefix" => "CustomPrefix"})
          expect(config.s3_path_prefix).to eq("CustomPrefix")
        end

        it "allows underscores and hyphens in s3_path_prefix" do
          config = Config.from_parsed_yaml("warehouse" => {"s3_path_prefix" => "Custom_Prefix-123"})
          expect(config.s3_path_prefix).to eq("Custom_Prefix-123")
        end
      end
    end
  end
end
