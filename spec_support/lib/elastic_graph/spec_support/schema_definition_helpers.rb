# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/json_ingestion/schema_definition/api_extension"
require "elastic_graph/schema_definition/test_support"

# Combines `:capture_logs` with `ElasticGraph::SchemaDefinition::TestSupport` in order
# to silence log output and fail if any tests result in logged warnings.
::RSpec.shared_context "SchemaDefinitionHelpers", :capture_logs do
  include ::ElasticGraph::SchemaDefinition::TestSupport

  def define_schema(
    schema_element_name_form:,
    schema_element_name_overrides: {},
    index_document_sizes: true,
    json_schema_version: 1,
    extension_modules: [ElasticGraph::JSONIngestion::SchemaDefinition::APIExtension],
    derived_type_name_formats: {},
    type_name_overrides: {},
    enum_value_overrides_by_type: {},
    reload_schema_artifacts: false,
    output: nil,
    &block
  )
    super(
      schema_element_name_form: schema_element_name_form,
      schema_element_name_overrides: schema_element_name_overrides,
      index_document_sizes: index_document_sizes,
      json_schema_version: json_schema_version,
      extension_modules: extension_modules,
      derived_type_name_formats: derived_type_name_formats,
      type_name_overrides: type_name_overrides,
      enum_value_overrides_by_type: enum_value_overrides_by_type,
      reload_schema_artifacts: reload_schema_artifacts,
      output: output || log_device,
      &block
    )
  end

  def define_schema_with_schema_elements(
    schema_elements,
    index_document_sizes: true,
    json_schema_version: 1,
    extension_modules: [ElasticGraph::JSONIngestion::SchemaDefinition::APIExtension],
    derived_type_name_formats: {},
    type_name_overrides: {},
    enum_value_overrides_by_type: {},
    reload_schema_artifacts: false,
    output: nil
  )
    super(
      schema_elements,
      index_document_sizes: index_document_sizes,
      json_schema_version: json_schema_version,
      extension_modules: extension_modules,
      derived_type_name_formats: derived_type_name_formats,
      type_name_overrides: type_name_overrides,
      enum_value_overrides_by_type: enum_value_overrides_by_type,
      reload_schema_artifacts: reload_schema_artifacts,
      output: output || log_device
    )
  end
end
