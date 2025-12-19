# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/errors"

module ElasticGraph
  module Warehouse
    class Lambda
      # Configuration for the Warehouse Lambda.
      #
      # @!attribute s3_path_prefix
      #   @return [String] The S3 path prefix to store the data under `dumped-data/`.
      class Config < ::Data.define(:s3_path_prefix)
        # @dynamic self.members
        EXPECTED_KEYS = members.map(&:to_s)
        S3_PATH_PREFIX_PATTERN = /\A[a-zA-Z0-9_-]+\z/

        def self.from_parsed_yaml(hash)
          warehouse = hash["warehouse"] || {}
          extra_keys = warehouse.keys - EXPECTED_KEYS

          unless extra_keys.empty?
            raise ::ElasticGraph::Errors::ConfigError, "Unknown `warehouse` config settings: #{extra_keys.join(", ")}"
          end

          s3_path_prefix = warehouse["s3_path_prefix"]

          if s3_path_prefix.nil? || s3_path_prefix.empty?
            raise ::ElasticGraph::Errors::ConfigSettingNotSetError,
              "`warehouse.s3_path_prefix` must be set in the configuration"
          end

          unless S3_PATH_PREFIX_PATTERN.match?(s3_path_prefix)
            raise ::ElasticGraph::Errors::ConfigError,
              "`warehouse.s3_path_prefix` must contain only alphanumeric characters, underscores, and hyphens (got: #{s3_path_prefix.inspect})"
          end

          new(s3_path_prefix: s3_path_prefix)
        end
      end
    end
  end
end
