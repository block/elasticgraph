# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/support/config"
require "elastic_graph/schema_artifacts/runtime_metadata/extension_loader"

module ElasticGraph
  module QueryInterceptor
    # Defines configuration for elasticgraph-query_interceptor
    class Config < Support::Config.define(:interceptors)
      json_schema at: "query_interceptor",
        optional: true,
        description: "Configuration of datastore query interceptors used by `elasticgraph-query_interceptor`.",
        properties: {
          interceptors: {
            description: "List of query interceptors to apply to datastore queries before they are executed.",
            type: "array",
            items: {
              type: "object",
              properties: {
                name: {
                  description: "The name of the interceptor extension class.",
                  type: "string",
                  pattern: /^[A-Z]\w+(::[A-Z]\w+)*$/.source, # https://rubular.com/r/UuqAz4fR3kdMip
                  examples: ["HideInternalRecordsInterceptor"]
                },
                require_path: {
                  description: "The path to require to load the interceptor extension. This should be a relative path from a directory on " \
                    "the Ruby `$LOAD_PATH` or a a relative path from the ElasticGraph application root.",
                  type: "string",
                  minLength: 1,
                  examples: ["./lib/interceptors/hide_internal_records_interceptor"]
                },
                config: {
                  description: "Configuration for the interceptor. Will be passed into the interceptors `#initialize` method.",
                  type: "object",
                  examples: [
                    {}, # : untyped
                    {"timeout" => 30}
                  ],
                  default: {} # : untyped
                }
              },
              required: ["name", "require_path"]
            },
            examples: [
              [], # : untyped
              [
                {
                  "name" => "HideInternalRecordsInterceptor",
                  "require_path" => "./lib/interceptors/hide_internal_records_interceptor"
                }
              ]
            ],
            default: [] # : untyped
          }
        }

      def with_runtime_metadata_configs(parsed_runtime_metadata_hashes)
        interceptor_hashes = parsed_runtime_metadata_hashes.flat_map { |h| h["interceptors"] || [] }
        return self if interceptor_hashes.empty?

        with(interceptors: interceptors + load_interceptors(interceptor_hashes))
      end

      private

      def convert_values(interceptors:)
        {interceptors: load_interceptors(interceptors)}
      end

      def load_interceptors(interceptor_hashes)
        loader = SchemaArtifacts::RuntimeMetadata::ExtensionLoader.new(InterceptorInterface)
        empty_config = {}  # : ::Hash[::Symbol, untyped]

        interceptor_hashes.map do |hash|
          ext = loader.load(hash.fetch("name"), from: hash.fetch("require_path"), config: empty_config)
          config = hash["config"] || {} # : ::Hash[::String, untyped]
          InterceptorData.new(klass: (_ = ext.extension_class), config: config)
        end
      end

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
