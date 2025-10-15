# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/warehouse/schema_definition/api_extension"

RSpec.describe ElasticGraph::Warehouse::WarehouseConfig::WarehouseTable, :unit do
  include ElasticGraph::SchemaDefinition::TestSupport

  it "handles non-null scalars" do
    require "elastic_graph/warehouse/schema_definition/api_extension"

    results = define_schema(
      schema_element_name_form: :snake_case,
      extension_modules: [ElasticGraph::Warehouse::SchemaDefinition::APIExtension]
    ) do |s|
      s.json_schema_version 1
      s.object_type "Doc" do |t|
        t.field "id", "ID!"
        t.warehouse_table "doc"
      end
    end

    table = results.warehouse_config.fetch("doc")
    expect(table.fetch("table_schema")).to include("id STRING")
  end

  it "handles arrays of non-null element types" do
    require "elastic_graph/warehouse/schema_definition/api_extension"

    results = define_schema(
      schema_element_name_form: :snake_case,
      extension_modules: [ElasticGraph::Warehouse::SchemaDefinition::APIExtension]
    ) do |s|
      s.json_schema_version 1
      s.object_type "Entry" do |t|
        t.field "tags", "[String!]"
        t.warehouse_table "entry"
      end
    end

    table = results.warehouse_config.fetch("entry")
    expect(table.fetch("table_schema")).to match("tags ARRAY<STRING>")
  end

  it "passes through custom settings in to_config" do
    require "elastic_graph/warehouse/schema_definition/api_extension"

    results = define_schema(
      schema_element_name_form: :snake_case,
      extension_modules: [ElasticGraph::Warehouse::SchemaDefinition::APIExtension]
    ) do |s|
      s.json_schema_version 1
      s.object_type "Event" do |t|
        t.field "id", "ID"
        t.field "createdDate", "Date"
        t.warehouse_table "event", retention_days: 14
      end
    end

    table = results.warehouse_config.fetch("event")
    expect(table.fetch("settings")).to include(retention_days: 14)
  end

  describe "edge cases for table_field methods" do
    it "handles list fields with unresolved types in table format" do
      require "elastic_graph/warehouse/schema_definition/api_extension"

      # Create a mock field with nil resolved type for a list
      mock_type = instance_double("Type")
      allow(mock_type).to receive(:list?).and_return(true)
      allow(mock_type).to receive(:unwrap_list).and_return(mock_type)
      allow(mock_type).to receive(:unwrap_non_null).and_return(mock_type)
      allow(mock_type).to receive(:resolved).and_return(nil)

      mock_field = instance_double("Field")
      allow(mock_field).to receive(:name).and_return("items")
      allow(mock_field).to receive(:type).and_return(mock_type)

      mock_indexed_type = instance_double("IndexedType")
      allow(mock_indexed_type).to receive(:indexing_fields_by_name_in_index).and_return(
        {"items" => mock_field}
      )

      table = ElasticGraph::Warehouse::WarehouseConfig::WarehouseTable.new(
        "test_table",
        {},
        instance_double("state"),
        mock_indexed_type
      )

      # Should return ARRAY<STRING> fallback for unresolved list type
      expect(table.table_schema).to include("items ARRAY<STRING>")
    end

    it "handles fields where resolved type does not respond to to_warehouse_field_type" do
      require "elastic_graph/warehouse/schema_definition/api_extension"

      # Create a mock resolved type that doesn't respond to to_warehouse_field_type
      mock_resolved = instance_double("ResolvedType")
      allow(mock_resolved).to receive(:respond_to?).with(:to_warehouse_column_type).and_return(false)

      mock_type = instance_double("Type")
      allow(mock_type).to receive(:list?).and_return(false)
      allow(mock_type).to receive(:unwrap_non_null).and_return(mock_type)
      allow(mock_type).to receive(:resolved).and_return(mock_resolved)

      mock_field = instance_double("Field")
      allow(mock_field).to receive(:name).and_return("custom_field")
      allow(mock_field).to receive(:type).and_return(mock_type)

      mock_indexed_type = instance_double("IndexedType")
      allow(mock_indexed_type).to receive(:indexing_fields_by_name_in_index).and_return(
        {"custom_field" => mock_field}
      )

      table = ElasticGraph::Warehouse::WarehouseConfig::WarehouseTable.new(
        "test_table",
        {},
        instance_double("state"),
        mock_indexed_type
      )

      # Should return STRING fallback for type without warehouse_field_type method
      expect(table.table_schema).to include("custom_field STRING")
    end
  end
end
