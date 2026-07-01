# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/json_ingestion/schema_definition/api_extension"

module ElasticGraph
  module JSONIngestionSchemaDefinition
    def define_schema(extension_modules: [], **options, &block)
      super(
        extension_modules: json_ingestion_schema_definition_extension_modules(extension_modules),
        **options,
        &block
      )
    end

    def define_schema_with_schema_elements(schema_elements, extension_modules: [], **options, &block)
      super(
        schema_elements,
        extension_modules: json_ingestion_schema_definition_extension_modules(extension_modules),
        **options,
        &block
      )
    end

    def generate_schema_artifacts(extension_modules: [], **options, &block)
      super(
        extension_modules: json_ingestion_schema_definition_extension_modules(extension_modules),
        **options,
        &block
      )
    end

    private

    def json_ingestion_schema_definition_extension_modules(extension_modules = [])
      [JSONIngestion::SchemaDefinition::APIExtension] | Array(extension_modules)
    end
  end

  RSpec.configure do |config|
    config.prepend JSONIngestionSchemaDefinition, :json_ingestion_schema_definition
  end
end
