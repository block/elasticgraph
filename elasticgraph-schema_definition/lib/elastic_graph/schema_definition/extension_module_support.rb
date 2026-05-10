# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  module SchemaDefinition
    # Helper methods for composing schema definition extension modules.
    #
    # @private
    module ExtensionModuleSupport
      # Default extension modules applied to {API} when none are explicitly specified. Currently this is
      # just `JSONIngestion::SchemaDefinition::APIExtension` (when `elasticgraph-json_ingestion` is installed).
      #
      # @return [Array<Module>] default extension modules — empty when no default ingestion serializer is installed.
      def self.default_extension_modules
        require "elastic_graph/json_ingestion/schema_definition/api_extension"
        [JSONIngestion::SchemaDefinition::APIExtension]
        # :nocov: -- only reached in bundles that exclude `elasticgraph-json_ingestion` (e.g. via
        # `Gemfile-custom`); not exercised by the standard test suite, where the gem is always present.
      rescue ::LoadError
        # `elasticgraph-json_ingestion` is an optional gem. When it isn't installed, fall back to no
        # default extension modules so that `elasticgraph-schema_definition` remains usable on its own.
        # The umbrella gems (e.g. `elasticgraph-local`) declare a runtime dep on `elasticgraph-json_ingestion`
        # to preserve backward compatibility for existing users.
        []
        # :nocov:
      end
    end
  end
end
