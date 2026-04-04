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
      module_function

      def default_ingestion_serializer_extension_modules
        require "elastic_graph/json_ingestion/schema_definition/api_extension"
        [JSONIngestion::SchemaDefinition::APIExtension]
      end

      def build_api_extension_modules(
        extension_modules:,
        ingestion_serializer_extension_modules: default_ingestion_serializer_extension_modules
      )
        (ingestion_serializer_extension_modules + extension_modules).uniq
      end
    end
  end
end
