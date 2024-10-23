# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

RSpec.describe ElasticGraph::Warehouse::SchemaDefinition::InterfaceTypeExtension, :unit do
  include ElasticGraph::SchemaDefinition::TestSupport

  it "allows defining a warehouse table on an interface type" do
    require "elastic_graph/warehouse/schema_definition/api_extension"

    results = define_schema(schema_element_name_form: :snake_case, extension_modules: [ElasticGraph::Warehouse::SchemaDefinition::APIExtension]) do |s|
      s.json_schema_version 1

      s.interface_type "Vehicle" do |t|
        t.field "id", "ID"
        t.field "manufacturer", "String"
        t.field "model", "String"
        t.warehouse_table "vehicles"
      end

      s.object_type "Car" do |t|
        t.implements "Vehicle"
        t.field "id", "ID"
        t.field "manufacturer", "String"
        t.field "model", "String"
        t.field "doors", "Int"
      end

      s.object_type "Motorcycle" do |t|
        t.implements "Vehicle"
        t.field "id", "ID"
        t.field "manufacturer", "String"
        t.field "model", "String"
        t.field "engine_cc", "Int"
      end
    end

    # Verify the warehouse table was created for the interface
    expect(results.warehouse_config).to have_key("vehicles")
    table = results.warehouse_config.fetch("vehicles")

    # Verify the table has the correct fields from the interface
    expect(table.fetch("table_schema")).to include("CREATE TABLE IF NOT EXISTS vehicles")
    expect(table.fetch("table_schema")).to include("id STRING")
    expect(table.fetch("table_schema")).to include("manufacturer STRING")
    expect(table.fetch("table_schema")).to include("model STRING")
  end

  it "converts interface type to warehouse field type" do
    require "elastic_graph/warehouse/schema_definition/api_extension"

    results = define_schema(schema_element_name_form: :snake_case, extension_modules: [ElasticGraph::Warehouse::SchemaDefinition::APIExtension]) do |s|
      s.json_schema_version 1

      s.interface_type "Addressable" do |t|
        t.field "street", "String"
        t.field "city", "String"
        t.field "postal_code", "String"
      end

      s.object_type "Building" do |t|
        t.implements "Addressable"
        t.field "street", "String"
        t.field "city", "String"
        t.field "postal_code", "String"
        t.field "floors", "Int"
      end

      s.object_type "Location" do |t|
        t.field "name", "String"
        t.field "address", "Addressable"
        t.warehouse_table "locations"
      end
    end

    # Verify that interface types can be used as field types
    table = results.warehouse_config.fetch("locations")
    expect(table.fetch("table_schema")).to include("address STRUCT<")
    expect(table.fetch("table_schema")).to include("street STRING")
    expect(table.fetch("table_schema")).to include("city STRING")
    expect(table.fetch("table_schema")).to include("postal_code STRING")
  end

  it "handles interface with nested object fields" do
    require "elastic_graph/warehouse/schema_definition/api_extension"

    results = define_schema(schema_element_name_form: :snake_case, extension_modules: [ElasticGraph::Warehouse::SchemaDefinition::APIExtension]) do |s|
      s.json_schema_version 1

      s.object_type "Coordinates" do |t|
        t.field "latitude", "Float"
        t.field "longitude", "Float"
      end

      s.interface_type "Locatable" do |t|
        t.field "name", "String"
        t.field "coordinates", "Coordinates"
        t.warehouse_table "locatable_items"
      end

      s.object_type "Store" do |t|
        t.implements "Locatable"
        t.field "name", "String"
        t.field "coordinates", "Coordinates"
        t.field "opening_hours", "String"
      end
    end

    table = results.warehouse_config.fetch("locatable_items")
    expect(table.fetch("table_schema")).to include("coordinates STRUCT<")
    expect(table.fetch("table_schema")).to include("latitude DOUBLE")
    expect(table.fetch("table_schema")).to include("longitude DOUBLE")
  end
end
