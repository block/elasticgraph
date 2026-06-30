# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/json_ingestion/schema_definition/api_extension"
require "elastic_graph/spec_support/schema_definition_helpers"

# Extends the shared "SchemaDefinitionHelpers" context to automatically apply this gem's
# `APIExtension` to every defined schema, since every spec in this gem exercises behavior
# provided by that extension. Additional extension modules can still be passed via
# `extension_modules:` and will be applied alongside it.
::RSpec.shared_context "JSONIngestionSchemaDefinitionHelpers" do
  include_context "SchemaDefinitionHelpers"

  def define_schema_with_schema_elements(schema_elements, extension_modules: [], output: nil, **options, &block)
    super(
      schema_elements,
      extension_modules: [::ElasticGraph::JSONIngestion::SchemaDefinition::APIExtension] | extension_modules,
      output: output || log_device,
      **options,
      &block
    )
  end
end
