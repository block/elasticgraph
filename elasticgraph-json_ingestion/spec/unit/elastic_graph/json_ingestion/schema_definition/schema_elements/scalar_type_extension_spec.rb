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

          it "does not infer a placeholder for JSON-safe unsigned_long scalars with the default coercion adapter (which would not coerce floats back to integers)" do
            grouping_missing_value_placeholder = grouping_missing_value_placeholder_for(
              "unsigned_long",
              type: "integer",
              maximum: JSON_SAFE_LONG_MAX
            )

            expect(grouping_missing_value_placeholder).to eq(nil)
          end

          it "does not infer a placeholder for unsigned_long scalars when no maximum is specified" do
            grouping_missing_value_placeholder = grouping_missing_value_placeholder_for("unsigned_long", type: "integer") do |type|
              type.coerce_with "ExampleScalarCoercionAdapter", defined_at: scalar_coercion_adapter_path
            end

            expect(grouping_missing_value_placeholder).to eq(nil)
          end

          it "infers a numeric missing-value placeholder for long scalars exactly at the JSON-safe boundaries with custom coercion" do
            grouping_missing_value_placeholder = grouping_missing_value_placeholder_for(
              "long",
              type: "integer",
              minimum: JSON_SAFE_LONG_MIN,
              maximum: JSON_SAFE_LONG_MAX
            ) do |type|
              type.coerce_with "ExampleScalarCoercionAdapter", defined_at: scalar_coercion_adapter_path
            end

            expect(grouping_missing_value_placeholder).to eq(MISSING_NUMERIC_PLACEHOLDER)
          end

          it "does not infer a placeholder for JSON-safe long scalars with the default coercion adapter" do
            grouping_missing_value_placeholder = grouping_missing_value_placeholder_for(
              "long",
              type: "integer",
              minimum: JSON_SAFE_LONG_MIN,
              maximum: JSON_SAFE_LONG_MAX
            )

            expect(grouping_missing_value_placeholder).to eq(nil)
          end

          it "does not infer a placeholder for long scalars when the minimum is one below the JSON-safe range" do
            grouping_missing_value_placeholder = grouping_missing_value_placeholder_for(
              "long",
              type: "integer",
              minimum: JSON_SAFE_LONG_MIN - 1,
              maximum: JSON_SAFE_LONG_MAX
            ) do |type|
              type.coerce_with "ExampleScalarCoercionAdapter", defined_at: scalar_coercion_adapter_path
            end

            expect(grouping_missing_value_placeholder).to eq(nil)
          end

          it "does not infer a placeholder for long scalars when the maximum is one above the JSON-safe range" do
            grouping_missing_value_placeholder = grouping_missing_value_placeholder_for(
              "long",
              type: "integer",
              minimum: JSON_SAFE_LONG_MIN,
              maximum: JSON_SAFE_LONG_MAX + 1
            ) do |type|
              type.coerce_with "ExampleScalarCoercionAdapter", defined_at: scalar_coercion_adapter_path
            end

            expect(grouping_missing_value_placeholder).to eq(nil)
          end

          it "does not infer a placeholder for long scalars when only one bound is specified (the other defaults to the LongString range)" do
            only_min = grouping_missing_value_placeholder_for("long", type: "integer", minimum: 0) do |type|
              type.coerce_with "ExampleScalarCoercionAdapter", defined_at: scalar_coercion_adapter_path
            end

            only_max = grouping_missing_value_placeholder_for("long", type: "integer", maximum: 1000) do |type|
              type.coerce_with "ExampleScalarCoercionAdapter", defined_at: scalar_coercion_adapter_path
            end

            expect(only_min).to eq(nil)
            expect(only_max).to eq(nil)
          end

          it "does not infer a placeholder for long scalars when no bounds are specified" do
            grouping_missing_value_placeholder = grouping_missing_value_placeholder_for("long", type: "integer") do |type|
              type.coerce_with "ExampleScalarCoercionAdapter", defined_at: scalar_coercion_adapter_path
            end

            expect(grouping_missing_value_placeholder).to eq(nil)
          end

          it "has the expected placeholder for each built-in scalar type, including the JSON-safe-range-aware `JsonSafeLong` inference" do
            results = define_schema(schema_element_name_form: "snake_case") { |schema| }
            built_in_scalars = results.state.scalar_types_by_name.keys
            scalar_types_by_name = results.runtime_metadata.scalar_types_by_name

            placeholders_by_scalar_type = built_in_scalars.to_h do |scalar_type|
              [scalar_type, scalar_types_by_name.fetch(scalar_type).grouping_missing_value_placeholder]
            end

            expect(placeholders_by_scalar_type).to eq({
              "Boolean" => nil,
              "Cursor" => MISSING_STRING_PLACEHOLDER,
              "Date" => nil,
              "DateTime" => nil,
              "Float" => MISSING_NUMERIC_PLACEHOLDER,
              "ID" => MISSING_STRING_PLACEHOLDER,
              "Int" => MISSING_NUMERIC_PLACEHOLDER, # GraphQL automatically coerces Int values
              "JsonSafeLong" => MISSING_NUMERIC_PLACEHOLDER, # custom coercion adapter coerces floats back to integers
              "LocalTime" => nil,
              "LongString" => nil, # outside of the JSON safe range.
              "String" => MISSING_STRING_PLACEHOLDER,
              "TimeZone" => MISSING_STRING_PLACEHOLDER,
              "Untyped" => MISSING_STRING_PLACEHOLDER
            })
          end

          def grouping_missing_value_placeholder_for(mapping_type, **json_schema_options)
            define_schema(schema_element_name_form: "snake_case") do |schema|
              schema.scalar_type "CustomScalar" do |type|
                type.mapping type: mapping_type
                type.json_schema(**json_schema_options)
                yield type if block_given?
              end
            end.runtime_metadata.scalar_types_by_name.fetch("CustomScalar").grouping_missing_value_placeholder
          end

          def scalar_coercion_adapter_path
            # Must match the `defined_at` path used by other specs (e.g. in `elasticgraph-schema_definition`)
            # that load this adapter: the extension loader raises if the same extension is loaded from two
            # different paths within one process, as can happen when one worker runs both suites.
            "support/example_extensions/scalar_coercion_adapter"
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
end
