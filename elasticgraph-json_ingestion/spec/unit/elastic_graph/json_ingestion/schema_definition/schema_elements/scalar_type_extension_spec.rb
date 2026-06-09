# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/constants"
require "elastic_graph/errors"
require "elastic_graph/json_ingestion/schema_definition/schema_elements/scalar_type_extension"
require "elastic_graph/spec_support/schema_definition_helpers"

module ElasticGraph
  module JSONIngestion
    module SchemaDefinition
      module SchemaElements
        RSpec.describe ScalarTypeExtension do
          include_context "SchemaDefinitionHelpers"

          it "requires custom scalar types to declare their JSON schema representation" do
            expect {
              define_schema(schema_element_name_form: "snake_case") do |schema|
                schema.scalar_type "BigInt" do |type|
                  type.mapping type: "long"
                end
              end
            }.to raise_error Errors::SchemaError, a_string_including("BigInt", "lacks `json_schema`")
          end

          it "extends schema elements created without customization blocks" do
            api = build_api
            api.enum_type "EmptyEnum"
            api.interface_type "EmptyInterface"
            direct_type_with_subfields = api.factory.new_type_with_subfields(
              :object,
              "DirectObject",
              wrapping_type: nil,
              field_factory: api.factory.method(:new_field)
            )

            # An enum's derived GraphQL types are built from a derived scalar twin, which can only be
            # built if `EnumTypeExtension` configured the twin's `json_schema`; otherwise building it
            # raises a "lacks `json_schema`" error.
            expect {
              api.state.enum_types_by_name.fetch("EmptyEnum").derived_graphql_types
            }.not_to raise_error

            # `json_schema` is only available on types extended with `TypeWithSubfieldsExtension`.
            interface_type = api.state.object_types_by_name.fetch("EmptyInterface")
            interface_type.json_schema minProperties: 1
            expect(interface_type.json_schema_options).to eq({minProperties: 1})

            direct_type_with_subfields.json_schema minProperties: 2
            expect(direct_type_with_subfields.json_schema_options).to eq({minProperties: 2})

            expect {
              build_api.scalar_type "BigInt"
            }.to raise_error Errors::SchemaError, a_string_including("BigInt", "lacks `json_schema`")
          end

          it "infers a numeric missing-value placeholder for JSON-safe unsigned_long scalars with custom coercion" do
            grouping_missing_value_placeholder = grouping_missing_value_placeholder_for(
              "unsigned_long",
              type: "integer",
              maximum: JSON_SAFE_LONG_MAX
            ) do |type|
              type.coerce_with "ExampleScalarCoercionAdapter", defined_at: scalar_coercion_adapter_path
            end

            expect(grouping_missing_value_placeholder).to eq(MISSING_NUMERIC_PLACEHOLDER)
          end

          it "does not infer a numeric missing-value placeholder for unsigned_long scalars outside the JSON-safe range" do
            grouping_missing_value_placeholder = grouping_missing_value_placeholder_for(
              "unsigned_long",
              type: "integer",
              maximum: JSON_SAFE_LONG_MAX + 1
            ) do |type|
              type.coerce_with "ExampleScalarCoercionAdapter", defined_at: scalar_coercion_adapter_path
            end

            expect(grouping_missing_value_placeholder).to eq(nil)
          end

          def grouping_missing_value_placeholder_for(mapping_type, **json_schema_options)
            define_schema(schema_element_name_form: "snake_case") do |schema|
              schema.scalar_type "CustomScalar" do |type|
                type.mapping type: mapping_type
                type.json_schema(**json_schema_options)
                yield type
              end
            end.runtime_metadata.scalar_types_by_name.fetch("CustomScalar").grouping_missing_value_placeholder
          end

          def scalar_coercion_adapter_path
            ::File.join(CommonSpecHelpers::REPO_ROOT, "elasticgraph-schema_definition/spec/support/example_extensions/scalar_coercion_adapter")
          end

          def build_api
            schema_elements = ::ElasticGraph::SchemaArtifacts::RuntimeMetadata::SchemaElementNames.new(form: "snake_case")
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
end
