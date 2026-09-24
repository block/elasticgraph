# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/errors"
require "elastic_graph/schema_artifacts/runtime_metadata/extension"
require "elastic_graph/schema_artifacts/runtime_metadata/extension_loader"

module ElasticGraph
  module SchemaArtifacts
    # Lazily builds extension-owned artifact providers. Each extension defines its own provider
    # interface and supplies matching implementations for disk and in-memory schema results.
    class ExtensionArtifacts
      # @private
      def initialize(extensions_by_name, &build_provider)
        @extensions_by_name = extensions_by_name
        @build_provider = build_provider
        @providers_by_name = {}
        @loader = RuntimeMetadata::ExtensionLoader.new(Factory)
      end

      # @param name [String] registered extension name
      # @return [Boolean] whether an artifact provider is registered, without loading it
      def key?(name)
        @extensions_by_name.key?(name)
      end

      # @param name [String] registered extension name
      # @return [Object] the extension's artifact provider, cached for this registry
      # @raise [Errors::MissingSchemaArtifactError] when the extension is not registered
      def fetch(name)
        @providers_by_name.fetch(name) do
          registration = @extensions_by_name.fetch(name) do
            raise Errors::MissingSchemaArtifactError, "No schema artifact extension is registered as `#{name}`. " \
              "Enable its schema definition extension and regenerate the schema artifacts."
          end
          extension = RuntimeMetadata::Extension.load_from_hash(registration.extension_ref, via: @loader)
          factory = extension.extension_class # : ::Module & _Factory
          @providers_by_name[name] = @build_provider.call(factory, extension.config)
        end
      end

      # Defines the factory interface implemented by schema artifact extensions.
      # Providers may expose any methods their consumers need; core imposes no format-specific API.
      module Factory
        # @param artifacts_dir [String] directory containing the saved schema artifacts
        # @param config [Hash] configuration supplied when registering the extension
        # @return [Object] a disk-backed artifact provider
        # simplecov:disable -- interface definition only
        def self.from_disk(artifacts_dir, config:)
        end

        # @param results [Object] in-memory schema definition results
        # @param config [Hash] configuration supplied when registering the extension
        # @return [Object] an in-memory artifact provider
        def self.from_schema_definition(results, config:)
        end
        # simplecov:enable
      end
    end
  end
end
