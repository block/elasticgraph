# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

RSpec.describe ElasticGraph::Warehouse::SchemaDefinition::ObjectTypeExtension, :unit do
  include ElasticGraph::SchemaDefinition::TestSupport

  it "allows defining a warehouse table on an object type" do
    require "elastic_graph/warehouse/schema_definition/api_extension"

    results = define_schema(schema_element_name_form: :snake_case, extension_modules: [ElasticGraph::Warehouse::SchemaDefinition::APIExtension]) do |s|
      s.json_schema_version 1

      s.object_type "Product" do |t|
        t.field "id", "ID"
        t.field "name", "String"
        t.warehouse_table "products"
      end
    end

    object_type = results.state.object_types_by_name["Product"]
    expect(object_type.warehouse_table_def).not_to be_nil
    expect(object_type.warehouse_table_def).to be_a(ElasticGraph::Warehouse::WarehouseConfig::WarehouseTable)
  end

  it "allows passing settings to warehouse_table" do
    require "elastic_graph/warehouse/schema_definition/api_extension"

    results = define_schema(schema_element_name_form: :snake_case, extension_modules: [ElasticGraph::Warehouse::SchemaDefinition::APIExtension]) do |s|
      s.json_schema_version 1

      s.object_type "Event" do |t|
        t.field "id", "ID"
        t.warehouse_table "events", retention_days: 30, partition_by: "date"
      end
    end

    table = results.warehouse_config.fetch("events")
    expect(table.fetch("settings")).to include(retention_days: 30, partition_by: "date")
  end

  it "allows passing a block to warehouse_table" do
    require "elastic_graph/warehouse/schema_definition/api_extension"

    results = define_schema(schema_element_name_form: :snake_case, extension_modules: [ElasticGraph::Warehouse::SchemaDefinition::APIExtension]) do |s|
      s.json_schema_version 1

      s.object_type "Order" do |t|
        t.field "id", "ID"
        t.warehouse_table "orders" do |table|
          # Block is yielded the warehouse table for customization
          expect(table).to be_a(ElasticGraph::Warehouse::WarehouseConfig::WarehouseTable)
        end
      end
    end

    expect(results.warehouse_config).to have_key("orders")
  end

  it "converts object type to warehouse field type" do
    require "elastic_graph/warehouse/schema_definition/api_extension"

    results = define_schema(schema_element_name_form: :snake_case, extension_modules: [ElasticGraph::Warehouse::SchemaDefinition::APIExtension]) do |s|
      s.json_schema_version 1

      s.object_type "Address" do |t|
        t.field "street", "String"
        t.field "city", "String"
        t.field "zip", "String"
      end

      s.object_type "Person" do |t|
        t.field "id", "ID"
        t.field "address", "Address"
        t.warehouse_table "people"
      end
    end

    object_type = results.state.object_types_by_name["Address"]
    field_type = object_type.to_warehouse_field_type

    expect(field_type).to be_a(ElasticGraph::Warehouse::WarehouseConfig::FieldType::Object)
    expect(field_type.type_name).to eq("Address")
  end

  it "handles nested object types in warehouse tables" do
    require "elastic_graph/warehouse/schema_definition/api_extension"

    results = define_schema(schema_element_name_form: :snake_case, extension_modules: [ElasticGraph::Warehouse::SchemaDefinition::APIExtension]) do |s|
      s.json_schema_version 1

      s.object_type "Location" do |t|
        t.field "lat", "Float"
        t.field "lng", "Float"
      end

      s.object_type "Venue" do |t|
        t.field "name", "String"
        t.field "location", "Location"
        t.warehouse_table "venues"
      end
    end

    table = results.warehouse_config.fetch("venues")
    expect(table.fetch("table_schema")).to include("location STRUCT<")
    expect(table.fetch("table_schema")).to include("lat DOUBLE")
    expect(table.fetch("table_schema")).to include("lng DOUBLE")
  end

  it "does not require warehouse_table to be defined" do
    require "elastic_graph/warehouse/schema_definition/api_extension"

    results = define_schema(schema_element_name_form: :snake_case, extension_modules: [ElasticGraph::Warehouse::SchemaDefinition::APIExtension]) do |s|
      s.json_schema_version 1

      s.object_type "NoWarehouse" do |t|
        t.field "id", "ID"
      end
    end

    object_type = results.state.object_types_by_name["NoWarehouse"]
    expect(object_type.warehouse_table_def).to be_nil
  end
end
