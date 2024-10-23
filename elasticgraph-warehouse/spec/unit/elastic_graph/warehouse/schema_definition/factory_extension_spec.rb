# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

RSpec.describe ElasticGraph::Warehouse::SchemaDefinition::FactoryExtension, :unit do
  include ElasticGraph::SchemaDefinition::TestSupport

  it "extends new object types with ObjectTypeExtension" do
    require "elastic_graph/warehouse/schema_definition/api_extension"

    results = define_schema(schema_element_name_form: :snake_case, extension_modules: [ElasticGraph::Warehouse::SchemaDefinition::APIExtension]) do |s|
      s.json_schema_version 1

      s.object_type "Product" do |t|
        t.field "id", "ID"
        t.field "name", "String"
        t.warehouse_table "products"
      end
    end

    expect(results.warehouse_config).to have_key("products")
  end

  it "extends new interface types with InterfaceTypeExtension" do
    require "elastic_graph/warehouse/schema_definition/api_extension"

    results = define_schema(schema_element_name_form: :snake_case, extension_modules: [ElasticGraph::Warehouse::SchemaDefinition::APIExtension]) do |s|
      s.json_schema_version 1

      s.interface_type "Node" do |t|
        t.field "id", "ID"
        t.warehouse_table "nodes"
      end
    end

    expect(results.warehouse_config).to have_key("nodes")
  end

  it "extends new scalar types with ScalarTypeExtension" do
    require "elastic_graph/warehouse/schema_definition/api_extension"

    results = define_schema(schema_element_name_form: :snake_case, extension_modules: [ElasticGraph::Warehouse::SchemaDefinition::APIExtension]) do |s|
      s.json_schema_version 1

      s.scalar_type "CustomDate" do |t|
        t.mapping type: "date"
        t.json_schema type: "string", format: "date"
      end

      s.object_type "Event" do |t|
        t.field "id", "ID"
        t.field "date", "CustomDate"
        t.warehouse_table "events"
      end
    end

    table = results.warehouse_config.fetch("events")
    expect(table.fetch("table_schema")).to include("date STRING")
  end

  it "extends new enum types with EnumTypeExtension" do
    require "elastic_graph/warehouse/schema_definition/api_extension"

    results = define_schema(schema_element_name_form: :snake_case, extension_modules: [ElasticGraph::Warehouse::SchemaDefinition::APIExtension]) do |s|
      s.json_schema_version 1

      s.enum_type "Status" do |t|
        t.value "ACTIVE"
        t.value "INACTIVE"
      end

      s.object_type "Account" do |t|
        t.field "id", "ID"
        t.field "status", "Status"
        t.warehouse_table "accounts"
      end
    end

    table = results.warehouse_config.fetch("accounts")
    expect(table.fetch("table_schema")).to include("status STRING")
  end

  it "handles object types without warehouse tables" do
    require "elastic_graph/warehouse/schema_definition/api_extension"

    results = define_schema(schema_element_name_form: :snake_case, extension_modules: [ElasticGraph::Warehouse::SchemaDefinition::APIExtension]) do |s|
      s.json_schema_version 1

      s.object_type "NoWarehouse" do |t|
        t.field "id", "ID"
        t.field "name", "String"
        # No warehouse_table call
      end

      s.object_type "WithWarehouse" do |t|
        t.field "id", "ID"
        t.warehouse_table "with_warehouse"
      end
    end

    expect(results.warehouse_config).not_to have_key("no_warehouse")
    expect(results.warehouse_config).to have_key("with_warehouse")
  end

  it "handles object types defined without a block" do
    require "elastic_graph/warehouse/schema_definition/api_extension"

    # Use define_schema to properly set up the API and factory
    results = define_schema(schema_element_name_form: :snake_case, extension_modules: [ElasticGraph::Warehouse::SchemaDefinition::APIExtension]) do |s|
      s.json_schema_version 1

      # Get the factory from the schema
      factory = s.factory

      # Call new_object_type without a block
      type = factory.new_object_type("NoBlockType")

      # Should still have warehouse extension methods
      expect(type).to respond_to(:warehouse_table)
      expect(type).to respond_to(:warehouse_table_def)
    end

    # Test passed if we get here without errors
    expect(results).not_to be_nil
  end
end
