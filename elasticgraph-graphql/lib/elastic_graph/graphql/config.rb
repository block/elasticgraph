# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/errors"
require "elastic_graph/graphql/client"
require "elastic_graph/schema_artifacts/runtime_metadata/extension_loader"

module ElasticGraph
  class GraphQL
    class Config < Data.define(
      # Determines the size of our datastore search requests if the query does not specify.
      :default_page_size,
      # Determines the maximum size of a requested page. If the client requests a page larger
      # than this value, `max_page_size` elements will be returned instead.
      :max_page_size,
      # Queries that take longer than this configured threshold will have a sanitized version logged.
      :slow_query_latency_warning_threshold_in_ms,
      # How to resolve nested relationships:
      #
      # - `optimized` (default): uses the new (in ElasticGraph 0.19.2.0) optimized resolver logic.
      # - `original`: uses the resolver logic from ElasticGraph v0.19.1.1 and before.
      # - `comparison`: runs both versions of the logic in serial, to compare them for correctness and performance. Results are logged.
      :nested_relationship_resolver_mode,
      # Object used to identify the client of a GraphQL query based on the HTTP request.
      :client_resolver,
      # Array of modules that will be extended onto the `GraphQL` instance to support extension libraries.
      :extension_modules,
      # Contains any additional settings that were in the settings file beyond settings that are expected as part of ElasticGraph
      # itself. Extensions are free to use these extra settings.
      :extension_settings
    )
      def self.from_parsed_yaml(entire_parsed_yaml)
        parsed_yaml = entire_parsed_yaml.fetch("graphql")
        extra_keys = parsed_yaml.keys - EXPECTED_KEYS

        unless extra_keys.empty?
          raise Errors::ConfigError, "Unknown `graphql` config settings: #{extra_keys.join(", ")}"
        end

        extension_loader = SchemaArtifacts::RuntimeMetadata::ExtensionLoader.new(::Module.new)
        extension_mods = parsed_yaml.fetch("extension_modules", []).map do |mod_hash|
          extension_loader.load(mod_hash.fetch("name"), from: mod_hash.fetch("require_path"), config: {}).extension_class.tap do |mod|
            unless mod.instance_of?(::Module)
              raise Errors::ConfigError, "`#{mod_hash.fetch("name")}` is not a module, but all application extension modules must be modules."
            end
          end
        end

        nested_relationship_resolver_mode = parsed_yaml["nested_relationship_resolver_mode"]&.to_sym || :optimized
        unless VALID_NESTED_RELATIONSHIP_RESOLVER_MODES.include?(nested_relationship_resolver_mode)
          raise Errors::ConfigError, "Invalid value for `nested_relationship_resolver_mode`: #{nested_relationship_resolver_mode}. " \
            "Valid values: #{VALID_NESTED_RELATIONSHIP_RESOLVER_MODES.join(", ")}."
        end

        new(
          default_page_size: parsed_yaml.fetch("default_page_size"),
          max_page_size: parsed_yaml.fetch("max_page_size"),
          slow_query_latency_warning_threshold_in_ms: parsed_yaml["slow_query_latency_warning_threshold_in_ms"] || 5000,
          nested_relationship_resolver_mode: nested_relationship_resolver_mode,
          client_resolver: load_client_resolver(parsed_yaml),
          extension_modules: extension_mods,
          extension_settings: entire_parsed_yaml.except(*ELASTICGRAPH_CONFIG_KEYS)
        )
      end

      # The keys we expect under `graphql`.
      EXPECTED_KEYS = members.map(&:to_s)

      # The standard ElasticGraph root config setting keys; anything else is assumed to be extension settings.
      ELASTICGRAPH_CONFIG_KEYS = %w[graphql indexer logger datastore schema_artifacts]

      VALID_NESTED_RELATIONSHIP_RESOLVER_MODES = [:optimized, :original, :comparison]

      private_class_method def self.load_client_resolver(parsed_yaml)
        config = parsed_yaml.fetch("client_resolver") do
          return Client::DefaultResolver.new({})
        end

        client_resolver_loader = SchemaArtifacts::RuntimeMetadata::ExtensionLoader.new(Client::DefaultResolver)
        extension = client_resolver_loader.load(
          config.fetch("name"),
          from: config.fetch("require_path"),
          config: config.except("name", "require_path")
        )
        extension_class = extension.extension_class # : ::Class

        __skip__ = extension_class.new(extension.config)
      end
    end
  end
end
