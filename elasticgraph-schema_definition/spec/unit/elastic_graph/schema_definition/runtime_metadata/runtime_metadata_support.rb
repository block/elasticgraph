# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/spec_support/schema_definition_helpers"
require "elastic_graph/spec_support/runtime_metadata_support"

module ElasticGraph
  module SchemaDefinition
    ::RSpec.shared_context "RuntimeMetadata support" do
      include_context "SchemaDefinitionHelpers"
      include SchemaArtifacts::RuntimeMetadata::RuntimeMetadataSupport

      def define_schema(**options, &block)
        super(schema_element_name_form: "snake_case", **options)
      end
    end
  end
end
