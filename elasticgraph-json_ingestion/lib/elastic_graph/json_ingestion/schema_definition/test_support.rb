# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/json_ingestion/schema_definition/api_extension"
require "elastic_graph/schema_artifacts/runtime_metadata/schema_element_names"
require "elastic_graph/schema_definition/test_support"

module ElasticGraph
  module JSONIngestion
    module SchemaDefinition
      # Mixin for tests that define schemas using the JSON ingestion extension. Supplements the base
      # {ElasticGraph::SchemaDefinition::TestSupport} by injecting {APIExtension} and defaulting the
      # JSON schema version (which {APIExtension} requires) so that tests need not set it explicitly.
      #
      # @private
      module TestSupport
        include ElasticGraph::SchemaDefinition::TestSupport

        # Mirrors the base signature but adds `json_schema_version` and builds the schema elements
        # itself, since the base `define_schema` doesn't thread `json_schema_version` through to
        # `define_schema_with_schema_elements`.
        def define_schema(schema_element_name_form:, schema_element_name_overrides: {}, json_schema_version: 1, **options, &block)
          schema_elements = SchemaArtifacts::RuntimeMetadata::SchemaElementNames.new(
            form: schema_element_name_form,
            overrides: schema_element_name_overrides
          )

          define_schema_with_schema_elements(schema_elements, json_schema_version: json_schema_version, **options, &block)
        end

        def define_schema_with_schema_elements(schema_elements, json_schema_version: 1, extension_modules: [], **options)
          super(schema_elements, extension_modules: [APIExtension] | Array(extension_modules), **options) do |base_api|
            api = base_api # : ElasticGraph::SchemaDefinition::API & APIExtension
            yield api if block_given?

            # Set the version only when the caller requested one and didn't set it themselves, so
            # that tests get a working default without triggering a "can only be set once" error.
            state = api.state # : ElasticGraph::SchemaDefinition::State & StateExtension
            api.json_schema_version(json_schema_version) if json_schema_version && state.json_schema_version.nil?
          end
        end
      end
    end
  end
end
