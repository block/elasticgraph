# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/spec_support/schema_definition_helpers"
require "elastic_graph/warehouse/schema_definition/api_extension"

module ElasticGraph
  module Warehouse
    module SchemaDefinition
      RSpec.describe FactoryExtension do
        include_context "SchemaDefinitionHelpers"

        it "extends enum types created without customization blocks" do
          define_schema(schema_element_name_form: "snake_case", extension_modules: [APIExtension]) do |api|
            api.enum_type "Status"

            expect(api.state.enum_types_by_name.fetch("Status")).to be_a(EnumTypeExtension)
          end
        end

        it "extends interface types created without customization blocks" do
          define_schema(schema_element_name_form: "snake_case", extension_modules: [APIExtension]) do |api|
            api.interface_type "Identifiable"

            expect(api.state.object_types_by_name.fetch("Identifiable")).to be_a(ObjectInterfaceAndUnionExtension)
          end
        end

        it "extends object types created without customization blocks" do
          define_schema(schema_element_name_form: "snake_case", extension_modules: [APIExtension]) do |api|
            api.object_type "Widget"

            expect(api.state.object_types_by_name.fetch("Widget")).to be_a(ObjectInterfaceAndUnionExtension)
          end
        end

        it "allows scalar type validation to fail normally without a customization block" do
          define_schema(schema_element_name_form: "snake_case", extension_modules: [APIExtension]) do |api|
            expect {
              api.scalar_type "Money"
            }.to raise_error(Errors::SchemaError, a_string_including("Scalar types require `mapping` to be configured"))
          end
        end

        it "extends union types created without customization blocks" do
          define_schema(schema_element_name_form: "snake_case", extension_modules: [APIExtension]) do |api|
            api.union_type "SearchResult"

            expect(api.state.object_types_by_name.fetch("SearchResult")).to be_a(ObjectInterfaceAndUnionExtension)
          end
        end
      end
    end
  end
end
