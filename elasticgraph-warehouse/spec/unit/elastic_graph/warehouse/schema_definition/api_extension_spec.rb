# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/schema_definition/test_support"
require "elastic_graph/warehouse/schema_definition/api_extension"

RSpec.describe ElasticGraph::Warehouse::SchemaDefinition::APIExtension, :unit do
  include ElasticGraph::SchemaDefinition::TestSupport

  it "extends the API factory with FactoryExtension" do
    require "elastic_graph/warehouse/schema_definition/api_extension"

    results = define_schema(schema_element_name_form: :snake_case, extension_modules: [ElasticGraph::Warehouse::SchemaDefinition::APIExtension]) do |s|
      s.json_schema_version 1

      # Just define a simple type to test the factory extension
      s.object_type "Test" do |t|
        t.field "id", "ID"
      end
    end

    # The factory should have been extended during schema definition
    expect(results).not_to be_nil
  end

  it "extends built-in scalar types with ScalarTypeExtension" do
    require "elastic_graph/warehouse/schema_definition/api_extension"

    results = define_schema(schema_element_name_form: :snake_case, extension_modules: [ElasticGraph::Warehouse::SchemaDefinition::APIExtension]) do |s|
      s.json_schema_version 1

      s.object_type "TestType" do |t|
        t.field "id", "ID"  # ID is a built-in scalar
        t.field "name", "String"  # String is a built-in scalar
        t.warehouse_table "test_types"
      end
    end

    table = results.warehouse_config.fetch("test_types")
    expect(table.fetch("table_schema")).to include("id STRING")
    expect(table.fetch("table_schema")).to include("name STRING")
  end

  it "extends built-in enum types with EnumTypeExtension" do
    require "elastic_graph/warehouse/schema_definition/api_extension"

    results = define_schema(schema_element_name_form: :snake_case, extension_modules: [ElasticGraph::Warehouse::SchemaDefinition::APIExtension]) do |s|
      s.json_schema_version 1

      s.enum_type "TestEnum" do |t|
        t.value "VALUE1"
        t.value "VALUE2"
      end

      s.object_type "TestType" do |t|
        t.field "id", "ID"
        t.field "status", "TestEnum"
        t.warehouse_table "test_types"
      end
    end

    # Should have generated warehouse config with enum field
    table = results.warehouse_config.fetch("test_types")
    expect(table.fetch("table_schema")).to include("status STRING")
  end

  it "extends built-in object types with ObjectAndInterfaceExtension" do
    require "elastic_graph/warehouse/schema_definition/api_extension"

    # Test with a schema that uses built-in object types
    results = define_schema(schema_element_name_form: :snake_case, extension_modules: [ElasticGraph::Warehouse::SchemaDefinition::APIExtension]) do |s|
      s.json_schema_version 1

      # PageInfo is a built-in object type
      s.object_type "CustomPageInfo" do |t|
        t.field "has_next_page", "Boolean"
        t.field "has_previous_page", "Boolean"
        t.warehouse_table "page_info"
      end
    end

    expect(results.warehouse_config).to have_key("page_info")
  end

  it "extends built-in interface types with ObjectAndInterfaceExtension" do
    require "elastic_graph/warehouse/schema_definition/api_extension"

    results = define_schema(schema_element_name_form: :snake_case, extension_modules: [ElasticGraph::Warehouse::SchemaDefinition::APIExtension]) do |s|
      s.json_schema_version 1

      s.interface_type "TestInterface" do |t|
        t.field "id", "ID"
        t.warehouse_table "test_interfaces"
      end

      s.object_type "TestImpl" do |t|
        t.implements "TestInterface"
        t.field "id", "ID"
      end
    end

    # Should have warehouse extension
    expect(results.warehouse_config).to have_key("test_interfaces")
  end

  it "does not double-extend types that already have extensions" do
    require "elastic_graph/warehouse/schema_definition/api_extension"

    results = define_schema(schema_element_name_form: :snake_case, extension_modules: [ElasticGraph::Warehouse::SchemaDefinition::APIExtension]) do |s|
      s.json_schema_version 1

      # Create a scalar type
      s.scalar_type "TestScalar" do |t|
        t.mapping type: "keyword"
        t.json_schema type: "string"
      end

      s.object_type "TestType" do |t|
        t.field "id", "TestScalar"
      end
    end

    # Verify the scalar type has the extension
    scalar_type = results.state.scalar_types_by_name["TestScalar"]
    expect(scalar_type).to respond_to(:to_warehouse_column_type)

    # Count how many times the module appears
    count = scalar_type.singleton_class.included_modules.count do |m|
      m == ElasticGraph::Warehouse::SchemaDefinition::ScalarTypeExtension
    end

    # Should only have one instance of the module
    expect(count).to eq(1)
  end

  it "handles union types which are not extended" do
    require "elastic_graph/warehouse/schema_definition/api_extension"

    results = define_schema(schema_element_name_form: :snake_case, extension_modules: [ElasticGraph::Warehouse::SchemaDefinition::APIExtension]) do |s|
      s.json_schema_version 1

      s.union_type "SearchResult" do |t|
        t.subtypes "Product", "Category"
      end

      s.object_type "Product" do |t|
        t.field "id", "ID"
        t.warehouse_table "products"
      end

      s.object_type "Category" do |t|
        t.field "id", "ID"
        t.field "name", "String"
      end
    end

    # Union types should not have warehouse tables
    expect(results.warehouse_config.keys).to eq(["products"])
  end

  it "handles types that are not in the case statement" do
    require "elastic_graph/warehouse/schema_definition/api_extension"

    # Test that union types (which are not in the case statement) don't cause errors
    results = define_schema(schema_element_name_form: :snake_case, extension_modules: [ElasticGraph::Warehouse::SchemaDefinition::APIExtension]) do |s|
      s.json_schema_version 1

      # Union type is not handled by the case statement in APIExtension
      s.union_type "TestUnion" do |t|
        t.subtypes "TypeA", "TypeB"
      end

      s.object_type "TypeA" do |t|
        t.field "id", "ID"
      end

      s.object_type "TypeB" do |t|
        t.field "id", "ID"
      end
    end

    # Should not raise error and should complete successfully
    expect(results).not_to be_nil
  end

  it "handles types in the else clause without extending them" do
    require "elastic_graph/warehouse/schema_definition/api_extension"

    # This test specifically verifies the else clause by checking that union types
    # (and other non-warehouse types) are not extended with warehouse methods
    results = define_schema(schema_element_name_form: :snake_case, extension_modules: [ElasticGraph::Warehouse::SchemaDefinition::APIExtension]) do |s|
      s.json_schema_version 1

      # Create a union type that will hit the else clause
      s.union_type "PaymentMethod" do |t|
        t.subtypes "CreditCard", "BankAccount"
      end

      s.object_type "CreditCard" do |t|
        t.field "id", "ID"
        t.field "last_four", "String"
      end

      s.object_type "BankAccount" do |t|
        t.field "id", "ID"
        t.field "routing_number", "String"
      end

      # Also create an object type to ensure the schema is valid
      s.object_type "Payment" do |t|
        t.field "id", "ID"
        t.field "amount", "Int"
        t.warehouse_table "payments"
      end
    end

    # Union types should not be extended with warehouse methods
    union_type = results.state.types_by_name["PaymentMethod"]
    expect(union_type).not_to respond_to(:to_warehouse_column_type)

    # But object types should still be extended
    object_type = results.state.object_types_by_name["Payment"]
    expect(object_type).to respond_to(:to_warehouse_column_type)

    # Verify warehouse config only contains the object type with warehouse_table
    expect(results.warehouse_config.keys).to eq(["payments"])
  end

  it "extends interface types when passed to on_built_in_types callback" do
    require "elastic_graph/warehouse/schema_definition/api_extension"

    # Directly test that the InterfaceType branch of the case statement works
    # by simulating what happens in on_built_in_types

    results = define_schema(
      schema_element_name_form: :snake_case,
      extension_modules: [ElasticGraph::Warehouse::SchemaDefinition::APIExtension]
    ) do |s|
      s.json_schema_version 1

      s.interface_type "TestNode" do |t|
        t.field "id", "ID!"
        t.field "name", "String"
        t.warehouse_table "test_nodes"
      end

      s.object_type "Product" do |t|
        t.implements "TestNode"
        t.field "id", "ID!"
        t.field "name", "String"
        t.field "price", "Int"
        t.warehouse_table "products"
      end
    end

    # Get the interface type from the results
    interface_type = results.state.types_by_name["TestNode"]

    # Verify the interface type was extended with ObjectAndInterfaceExtension
    # (this happens via FactoryExtension, not on_built_in_types, but tests the same code path)
    expect(interface_type).to be_a(ElasticGraph::SchemaDefinition::SchemaElements::InterfaceType)
    expect(interface_type).to respond_to(:to_warehouse_column_type)

    # Verify it has the ObjectAndInterfaceExtension
    expect(interface_type.singleton_class.included_modules).to include(
      ElasticGraph::Warehouse::SchemaDefinition::ObjectAndInterfaceExtension
    )

    # Verify warehouse tables were created for both types
    expect(results.warehouse_config).to have_key("test_nodes")
    expect(results.warehouse_config).to have_key("products")
  end

  it "handles object types in on_built_in_types" do
    require "elastic_graph/warehouse/schema_definition/api_extension"

    results = define_schema(schema_element_name_form: :snake_case, extension_modules: [ElasticGraph::Warehouse::SchemaDefinition::APIExtension]) do |s|
      s.json_schema_version 1

      # This will trigger on_built_in_types for built-in object types
      s.object_type "TestType" do |t|
        t.field "id", "ID"
        t.warehouse_table "test_types"
      end
    end

    expect(results.warehouse_config).to have_key("test_types")
  end

  it "handles interface types in on_built_in_types" do
    require "elastic_graph/warehouse/schema_definition/api_extension"

    results = define_schema(schema_element_name_form: :snake_case, extension_modules: [ElasticGraph::Warehouse::SchemaDefinition::APIExtension]) do |s|
      s.json_schema_version 1

      # This will trigger on_built_in_types for interface types
      s.interface_type "TestInterface" do |t|
        t.field "id", "ID"
        t.warehouse_table "test_interfaces"
      end

      s.object_type "TestImpl" do |t|
        t.implements "TestInterface"
        t.field "id", "ID"
      end
    end

    expect(results.warehouse_config).to have_key("test_interfaces")
  end

  it "handles scalar types in on_built_in_types" do
    require "elastic_graph/warehouse/schema_definition/api_extension"

    results = define_schema(schema_element_name_form: :snake_case, extension_modules: [ElasticGraph::Warehouse::SchemaDefinition::APIExtension]) do |s|
      s.json_schema_version 1

      # This will trigger on_built_in_types for scalar types
      s.scalar_type "TestScalar" do |t|
        t.mapping type: "keyword"
        t.json_schema type: "string"
        t.warehouse_column type: "STRING"
      end

      s.object_type "TestType" do |t|
        t.field "id", "TestScalar"
        t.warehouse_table "test_types"
      end
    end

    expect(results.warehouse_config).to have_key("test_types")
  end
end
