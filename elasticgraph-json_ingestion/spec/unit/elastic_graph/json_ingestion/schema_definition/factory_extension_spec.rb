# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/json_ingestion/schema_definition/api_extension"
require "elastic_graph/spec_support/schema_definition_helpers"

module ElasticGraph
  module JSONIngestion
    module SchemaDefinition
      RSpec.describe FactoryExtension do
        include_context "SchemaDefinitionHelpers"

        it "extends enum types created without customization blocks" do
          api = build_api
          api.enum_type "EmptyEnum"

          # An enum's derived GraphQL types are built from a derived scalar twin, which can only be
          # built if `EnumTypeExtension` configured the twin's `json_schema`; otherwise building it
          # raises a "lacks `json_schema`" error.
          expect {
            api.state.enum_types_by_name.fetch("EmptyEnum").derived_graphql_types
          }.not_to raise_error
        end

        it "extends interface types created without customization blocks" do
          api = build_api
          api.interface_type "EmptyInterface"

          interface_type = api.state.object_types_by_name.fetch("EmptyInterface")
          interface_type.json_schema minProperties: 1

          expect(interface_type.json_schema_options).to eq({minProperties: 1})
        end

        def build_api
          schema_elements = SchemaArtifacts::RuntimeMetadata::SchemaElementNames.new(form: "snake_case")
          ::ElasticGraph::SchemaDefinition::API.new(
            schema_elements,
            true,
            extension_modules: [APIExtension],
            output: log_device
          )
        end
      end
    end
  end
end
