# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  module JSONIngestion
    module SchemaDefinition
      RSpec.describe FactoryExtension do
        it "extends enum types created without customization blocks" do
          define_schema(schema_element_name_form: "snake_case") do |api|
            # Create the enum without a customization block (the case being exercised), then add a
            # value afterward so the schema is valid (enums must have at least one value).
            api.enum_type "SomeEnum"
            enum_type = api.state.enum_types_by_name.fetch("SomeEnum")
            enum_type.value "SOME_VALUE"

            # An enum's derived GraphQL types are built from a derived scalar twin, which can only be
            # built if `EnumTypeExtension` configured the twin's `json_schema`; otherwise building it
            # raises a "lacks `json_schema`" error.
            expect {
              enum_type.derived_graphql_types
            }.not_to raise_error
          end
        end

        it "extends interface types created without customization blocks" do
          define_schema(schema_element_name_form: "snake_case") do |api|
            api.interface_type "EmptyInterface"

            interface_type = api.state.object_types_by_name.fetch("EmptyInterface")
            interface_type.json_schema minProperties: 1

            expect(interface_type.json_schema_options).to eq({minProperties: 1})
          end
        end
      end
    end
  end
end
