# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/spec_support/schema_definition_helpers"

module ElasticGraph
  module SchemaDefinition
    ::RSpec.shared_context "IndexDefinitionSpecSupport" do
      include_context "SchemaDefinitionHelpers"

      def index_configs_for(*index_names, index_document_sizes: false, schema_element_name_form: "snake_case", &schema_definition)
        config = define_schema(
          index_document_sizes: index_document_sizes,
          schema_element_name_form: schema_element_name_form,
          &schema_definition
        ).datastore_config

        index_names.map { |i| config.fetch("indices").fetch(i) }
      end

      def index_template_configs_for(*index_names, index_document_sizes: false, schema_element_name_form: "snake_case", &schema_definition)
        config = define_schema(
          index_document_sizes: index_document_sizes,
          schema_element_name_form: schema_element_name_form,
          &schema_definition
        ).datastore_config

        index_names.map { |i| config.fetch("index_templates").fetch(i) }
      end
    end
  end
end
