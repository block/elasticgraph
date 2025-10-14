# frozen_string_literal: true

require "elastic_graph/errors"

module ElasticGraph
  class WarehouseLambda
    class Config < ::Data.define(
        # The s3 path prefix to store the data.
        :s3_path_prefix
      )

      def self.from_parsed_yaml(hash)
        warehouse = hash["warehouse"] || {}
        extra_keys = warehouse.keys - EXPECTED_KEYS

        unless extra_keys.empty?
          raise ::ElasticGraph::Errors::ConfigError, "Unknown `warehouse` config settings: #{extra_keys.join(", ")}"
        end

        s3_path_prefix = warehouse["s3_path_prefix"] || "Data001"
        new(s3_path_prefix: s3_path_prefix)
      end

      EXPECTED_KEYS = members.map(&:to_s)
    end
  end
end
