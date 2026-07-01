# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/json_ingestion/schema_definition/api_extension"
require "elastic_graph/json_ingestion/schema_definition/test_support"

module ElasticGraph
  # Wires the JSON ingestion schema definition support into specs tagged
  # `:json_ingestion_schema_definition`. Mixing in
  # {JSONIngestion::SchemaDefinition::TestSupport} overrides `define_schema` /
  # `define_schema_with_schema_elements` to inject `APIExtension` and default the JSON schema version.
  # `generate_schema_artifacts` is handled separately below because it calls `TestSupport.define_schema`
  # as a module method (which the instance-level mixin doesn't reach).
  module JSONIngestionSchemaDefinition
    include JSONIngestion::SchemaDefinition::TestSupport

    def generate_schema_artifacts(extension_modules: [], **options)
      super(extension_modules: json_ingestion_schema_definition_extension_modules(extension_modules), **options) do |schema|
        yield schema

        # Default the JSON schema version (which `APIExtension` requires) unless the block set it,
        # so specs need not set it explicitly. Mirrors the `define_schema*` behavior in
        # {JSONIngestion::SchemaDefinition::TestSupport}.
        schema.json_schema_version(1) if schema.state.json_schema_version.nil?
      end
    end

    private

    # Prepends `APIExtension` to the given `extension_modules`. Useful for specs that construct
    # schema-definition machinery directly (e.g. `RakeTasks.new`) rather than via `define_schema`.
    def json_ingestion_schema_definition_extension_modules(extension_modules = [])
      [JSONIngestion::SchemaDefinition::APIExtension] | Array(extension_modules)
    end
  end

  RSpec.configure do |config|
    config.include JSONIngestionSchemaDefinition, :json_ingestion_schema_definition
  end
end
