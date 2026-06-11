# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/schema_definition/test_support"

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

  # `default_schema_definition_extension_modules` is provided by `CommonSpecHelpers`, which performs
  # the `elasticgraph-json_ingestion` require lazily so this file can be loaded in spec bundles that
  # do not include that optional gem.
end
