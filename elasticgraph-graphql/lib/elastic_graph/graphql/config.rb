# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/support/config"
require "elastic_graph/errors"
require "elastic_graph/graphql/client"
require "elastic_graph/schema_artifacts/runtime_metadata/extension_loader"

module ElasticGraph
  class GraphQL
    class Config < Support::Config.define(
      :default_page_size,
      :max_page_size,
      :slow_query_latency_warning_threshold_in_ms,
      :client_resolver,
      :extension_modules,
      :extension_settings
    )
      all_json_schema_types = ["array", "string", "number", "boolean", "object", "null"]

      json_schema at: "graphql",
        optional: false,
        description: "Configuration for GraphQL behavior used by `elasticgraph-graphql`.",
        properties: {
          default_page_size: {
            description: "Determines the `size` of our datastore search requests if the query does not specify via `first` or `last`.",
            type: "integer",
            minimum: 1,
            default: 50,
            examples: [25, 50, 100]
          },
          max_page_size: {
            description: "Determines the maximum size of a requested page. If the client requests a page larger " \
              "than this value, the `size` will be capped by this value.",
            type: "integer",
            minimum: 1,
            default: 500,
            examples: [100, 500, 1000]
          },
          slow_query_latency_warning_threshold_in_ms: {
            description: "Queries that take longer than this configured threshold will have a sanitized version logged so that they can be investigated.",
            type: "integer",
            minimum: 0,
            default: 5000,
            examples: [3000, 5000, 10000]
          },
          client_resolver: {
            description: "Object used to identify the client of a GraphQL query based on the HTTP request.",
            type: "object",
            properties: {
              name: {
                description: "Name of the client resolver class.",
                type: ["string", "null"],
                minLength: 1,
                default: nil,
                examples: [nil, "MyCompany::ElasticGraphClientResolver"]
              },
              require_path: {
                description: "The path to require to load the client resolver class.",
                type: ["string", "null"],
                minLength: 1,
                default: nil,
                examples: [nil, "./lib/my_company/elastic_graph/client_resolver"]
              }
            },
            patternProperties: {/.+/.source => {type: all_json_schema_types}},
            default: {}, # : untyped
            examples: [
              {}, # : untyped
              {
                "name" => "ElasticGraph::GraphQL::ClientResolvers::ViaHTTPHeader",
                "require_path" => "support/client_resolvers",
                "header_name" => "X-Client-Name"
              }
            ]
          },
          extension_modules: {
            description: "Array of modules that will be extended onto the `GraphQL` instance to support extension libraries.",
            type: "array",
            items: {
              type: "object",
              properties: {
                name: {
                  type: "string",
                  minLength: 1,
                  description: "The name of the extension module class to load.",
                  examples: ["MyExtensionModule", "ElasticGraph::MyExtension"]
                },
                require_path: {
                  type: "string",
                  minLength: 1,
                  description: "The path to require to load the extension module.",
                  examples: ["./my_extension_module", "elastic_graph/my_extension"]
                }
              },
              required: ["name", "require_path"]
            },
            default: [], # : untyped
            examples: [
              [], # : untyped
              [
                {
                  "name" => "MyExtensionModule",
                  "require_path" => "./my_extension_module"
                }
              ]
            ]
          }
        }

      # The standard ElasticGraph root config setting keys; anything else is assumed to be extension settings.
      ELASTICGRAPH_CONFIG_KEYS = %w[graphql indexer logger datastore schema_artifacts]

      def self.from_parsed_yaml(parsed_yaml)
        original = super(parsed_yaml)
        return nil if original.nil?

        extension_settings = original.extension_settings.merge(parsed_yaml.except(*ELASTICGRAPH_CONFIG_KEYS))
        original.with(extension_settings: extension_settings)
      end

      private

      def convert_values(client_resolver:, extension_modules:, **values)
        client_resolver = load_client_resolver(client_resolver)
        extension_modules = load_extension_modules(extension_modules)

        values.merge({
          client_resolver: client_resolver,
          extension_modules: extension_modules,
          extension_settings: {} # : parsedYamlSettings
        })
      end

      def load_client_resolver(config)
        return Client::DefaultResolver.new({}) if config.empty?

        client_resolver_loader = SchemaArtifacts::RuntimeMetadata::ExtensionLoader.new(Client::DefaultResolver)
        extension = client_resolver_loader.load(
          config.fetch("name"),
          from: config.fetch("require_path"),
          config: config.except("name", "require_path")
        )
        extension_class = extension.extension_class # : ::Class

        __skip__ = extension_class.new(extension.config)
      end

      def load_extension_modules(extension_module_hashes)
        extension_loader = SchemaArtifacts::RuntimeMetadata::ExtensionLoader.new(::Module.new)

        extension_module_hashes.map do |mod_hash|
          extension_loader.load(mod_hash.fetch("name"), from: mod_hash.fetch("require_path"), config: {}).extension_class.tap do |mod|
            unless mod.instance_of?(::Module)
              raise Errors::ConfigError, "`#{mod_hash.fetch("name")}` is not a module, but all application extension modules must be modules."
            end
          end
        end
      end
    end
  end
end
