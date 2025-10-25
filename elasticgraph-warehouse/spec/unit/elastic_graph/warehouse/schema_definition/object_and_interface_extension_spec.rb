# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/warehouse/schema_definition/api_extension"

RSpec.describe ElasticGraph::Warehouse::SchemaDefinition::ObjectAndInterfaceExtension, :unit do
  include ElasticGraph::SchemaDefinition::TestSupport

  describe "object types" do
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

    it "converts object type to warehouse column type" do
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
      table_type = object_type.to_warehouse_column_type

      expect(table_type).to be_a(String)
      expect(table_type).to start_with("STRUCT<")
      expect(table_type).to include("street STRING", "city STRING", "zip STRING")
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
          t.field "id", "ID"
          t.field "name", "String"
          t.field "location", "Location"
          t.warehouse_table "venues"
        end
      end

      table = results.warehouse_config.fetch("venues")
      expect(table.fetch("table_schema")).to include("location STRUCT<lat DOUBLE, lng DOUBLE>")
    end
  end

  describe "interface types" do
    it "allows defining a warehouse table on an interface type" do
      require "elastic_graph/warehouse/schema_definition/api_extension"

      results = define_schema(schema_element_name_form: :snake_case, extension_modules: [ElasticGraph::Warehouse::SchemaDefinition::APIExtension]) do |s|
        s.json_schema_version 1

        s.interface_type "Node" do |t|
          t.field "id", "ID"
          t.warehouse_table "nodes"
        end

        s.object_type "User" do |t|
          t.implements "Node"
          t.field "id", "ID"
          t.field "name", "String"
        end
      end

      interface_type = results.state.types_by_name["Node"]
      expect(interface_type.warehouse_table_def).not_to be_nil
      expect(interface_type.warehouse_table_def).to be_a(ElasticGraph::Warehouse::WarehouseConfig::WarehouseTable)
    end

    it "allows passing settings to warehouse_table on interface" do
      require "elastic_graph/warehouse/schema_definition/api_extension"

      results = define_schema(schema_element_name_form: :snake_case, extension_modules: [ElasticGraph::Warehouse::SchemaDefinition::APIExtension]) do |s|
        s.json_schema_version 1

        s.interface_type "Timestamped" do |t|
          t.field "createdAt", "DateTime"
          t.warehouse_table "timestamped_entities", retention_days: 90
        end

        s.object_type "Post" do |t|
          t.implements "Timestamped"
          t.field "id", "ID"
          t.field "createdAt", "DateTime"
        end
      end

      table = results.warehouse_config.fetch("timestamped_entities")
      expect(table.fetch("settings")).to include(retention_days: 90)
    end

    it "converts interface type to warehouse column type" do
      require "elastic_graph/warehouse/schema_definition/api_extension"

      results = define_schema(schema_element_name_form: :snake_case, extension_modules: [ElasticGraph::Warehouse::SchemaDefinition::APIExtension]) do |s|
        s.json_schema_version 1

        s.interface_type "Identifiable" do |t|
          t.field "id", "ID"
          t.field "name", "String"
        end

        s.object_type "Product" do |t|
          t.implements "Identifiable"
          t.field "id", "ID"
          t.field "name", "String"
          t.field "price", "Float"
          t.warehouse_table "products"
        end
      end

      interface_type = results.state.types_by_name["Identifiable"]
      table_type = interface_type.to_warehouse_column_type

      expect(table_type).to be_a(String)
      expect(table_type).to start_with("STRUCT<")
      expect(table_type).to include("id STRING", "name STRING")
    end
  end
end
