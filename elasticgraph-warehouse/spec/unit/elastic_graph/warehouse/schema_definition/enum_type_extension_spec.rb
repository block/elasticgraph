# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/warehouse/schema_definition/api_extension"

RSpec.describe ElasticGraph::Warehouse::SchemaDefinition::EnumTypeExtension, :unit do
  include ElasticGraph::SchemaDefinition::TestSupport

  it "converts enum type to warehouse table type" do
    require "elastic_graph/warehouse/schema_definition/api_extension"

    results = define_schema(schema_element_name_form: :snake_case, extension_modules: [ElasticGraph::Warehouse::SchemaDefinition::APIExtension]) do |s|
      s.json_schema_version 1

      s.enum_type "Status" do |t|
        t.value "ACTIVE"
        t.value "INACTIVE"
        t.value "PENDING"
      end

      s.object_type "Item" do |t|
        t.field "id", "ID"
        t.field "status", "Status"
        t.warehouse_table "items"
      end
    end

    enum_type = results.state.enum_types_by_name["Status"]
    table_type = enum_type.to_warehouse_column_type

    expect(table_type).to eq("STRING")
  end

  it "maps enum types to STRING in warehouse tables" do
    require "elastic_graph/warehouse/schema_definition/api_extension"

    results = define_schema(schema_element_name_form: :snake_case, extension_modules: [ElasticGraph::Warehouse::SchemaDefinition::APIExtension]) do |s|
      s.json_schema_version 1

      s.enum_type "Priority" do |t|
        t.value "LOW"
        t.value "MEDIUM"
        t.value "HIGH"
      end

      s.object_type "Task" do |t|
        t.field "id", "ID"
        t.field "priority", "Priority"
        t.warehouse_table "tasks"
      end
    end

    table = results.warehouse_config.fetch("tasks")
    expect(table.fetch("table_schema")).to include("priority STRING")
  end

  it "handles enum types with many values" do
    require "elastic_graph/warehouse/schema_definition/api_extension"

    results = define_schema(schema_element_name_form: :snake_case, extension_modules: [ElasticGraph::Warehouse::SchemaDefinition::APIExtension]) do |s|
      s.json_schema_version 1

      s.enum_type "Country" do |t|
        t.value "USA"
        t.value "CANADA"
        t.value "MEXICO"
        t.value "UK"
        t.value "FRANCE"
        t.value "GERMANY"
      end

      s.object_type "Address" do |t|
        t.field "id", "ID"
        t.field "country", "Country"
        t.warehouse_table "addresses"
      end
    end

    enum_type = results.state.enum_types_by_name["Country"]
    table_type = enum_type.to_warehouse_column_type

    expect(table_type).to eq("STRING")
  end
end
