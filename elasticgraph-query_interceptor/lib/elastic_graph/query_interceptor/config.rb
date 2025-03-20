# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/schema_artifacts/runtime_metadata/extension_loader"

module ElasticGraph
  module QueryInterceptor
    # Defines configuration for elasticgraph-query_interceptor
    class Config < ::Data.define(:interceptors)
      # Builds Config from parsed YAML config.
      def self.from_parsed_yaml(parsed_config_hash, parsed_runtime_metadata_hashes: [])
        interceptor_hashes = parsed_runtime_metadata_hashes.flat_map { |h| h["interceptors"] || [] }

        if (extension_config = parsed_config_hash["query_interceptor"])
          extra_keys = extension_config.keys - EXPECTED_KEYS

          unless extra_keys.empty?
            raise Errors::ConfigError, "Unknown `query_interceptor` config settings: #{extra_keys.join(", ")}"
          end

          interceptor_hashes += extension_config.fetch("interceptors")
        end

        loader = SchemaArtifacts::RuntimeMetadata::ExtensionLoader.new(InterceptorInterface)

        interceptors = interceptor_hashes.map do |hash|
          empty_config = {}  # : ::Hash[::Symbol, untyped]
          ext = loader.load(hash.fetch("extension_name"), from: hash.fetch("require_path"), config: empty_config)
          config = hash["config"] || {} # : ::Hash[::String, untyped]
          InterceptorData.new(klass: ext.extension_class, config: config)
        end

        new(interceptors)
      end

      DEFAULT = new([])
      EXPECTED_KEYS = members.map(&:to_s)

      # Defines a data structure to hold interceptor klass and config
      InterceptorData = ::Data.define(:klass, :config)

      # Defines the interceptor interface, which our extension loader will validate against.
      class InterceptorInterface
        def initialize(elasticgraph_graphql:, config:)
          # must be defined, but nothing to do
        end

        def intercept(query, field:, args:, http_request:, context:)
          # :nocov: -- must return a query to satisfy Steep type checking but never called
          query
          # :nocov:
        end
      end
    end
  end
end
