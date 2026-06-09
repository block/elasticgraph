# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/schema_definition/test_support"

module ElasticGraph
  module SpecSupport
    DEFAULT_SCHEMA_DEFINITION_EXTENSION_MODULES = begin
      require "elastic_graph/json_ingestion/schema_definition/api_extension"
      [::ElasticGraph::JSONIngestion::SchemaDefinition::APIExtension]
    rescue LoadError => e
      # :nocov: -- per-gem spec bundles may not include the optional `elasticgraph-json_ingestion` gem.
      raise unless e.path == "elastic_graph/json_ingestion/schema_definition/api_extension"

      []
      # :nocov:
    end.freeze
  end
end

# Combines `:capture_logs` with `ElasicGraph::SchemaDefinition::TestSupport` in order
# to silence log output and fail if any tests result in logged warnings.
::RSpec.shared_context "SchemaDefinitionHelpers", :capture_logs do
  include ::ElasticGraph::SchemaDefinition::TestSupport

  # Defaults `extension_modules` and `output` for tests; all other options are forwarded to
  # `TestSupport` unchanged. `output` must be handled with `||` (rather than a keyword default)
  # because `TestSupport#define_schema` passes `output: nil` explicitly when no output is given.
  def define_schema(extension_modules: default_schema_definition_extension_modules, output: nil, **options, &block)
    super(
      extension_modules: extension_modules,
      output: output || log_device,
      **options,
      &block
    )
  end

  def define_schema_with_schema_elements(schema_elements, extension_modules: default_schema_definition_extension_modules, output: nil, **options, &block)
    super(
      schema_elements,
      extension_modules: extension_modules,
      output: output || log_device,
      **options,
      &block
    )
  end

  def default_schema_definition_extension_modules
    ::ElasticGraph::SpecSupport::DEFAULT_SCHEMA_DEFINITION_EXTENSION_MODULES.dup
  end
end
