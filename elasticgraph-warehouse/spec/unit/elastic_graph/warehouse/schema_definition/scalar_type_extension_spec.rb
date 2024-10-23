# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

RSpec.describe ElasticGraph::Warehouse::SchemaDefinition::ScalarTypeExtension, :unit do
  include ElasticGraph::SchemaDefinition::TestSupport

  it "allows configuring warehouse table options on scalar types" do
    require "elastic_graph/warehouse/schema_definition/api_extension"

    results = define_schema(schema_element_name_form: :snake_case, extension_modules: [ElasticGraph::Warehouse::SchemaDefinition::APIExtension]) do |s|
      s.json_schema_version 1

      s.scalar_type "CustomTimestamp" do |t|
        t.mapping type: "date"
        t.json_schema type: "string", format: "date-time"
        t.warehouse_table type: "TIMESTAMP"
      end

      s.object_type "Event" do |t|
        t.field "id", "ID"
        t.field "occurred_at", "CustomTimestamp"
        t.warehouse_table "events"
      end
    end

    # Verify the scalar type has warehouse options
    scalar_type = results.state.scalar_types_by_name["CustomTimestamp"]
    expect(scalar_type.warehouse_table_options).to eq({type: "TIMESTAMP"})
  end

  it "merges hash argument with keyword arguments in warehouse_table" do
    require "elastic_graph/warehouse/schema_definition/api_extension"

    results = define_schema(schema_element_name_form: :snake_case, extension_modules: [ElasticGraph::Warehouse::SchemaDefinition::APIExtension]) do |s|
      s.json_schema_version 1

      s.scalar_type "CustomDecimal" do |t|
        t.mapping type: "scaled_float"
        t.json_schema type: "number"
        t.warehouse_table({precision: 10}, scale: 2)
      end

      s.object_type "Price" do |t|
        t.field "amount", "CustomDecimal"
        t.warehouse_table "prices"
      end
    end

    scalar_type = results.state.scalar_types_by_name["CustomDecimal"]
    expect(scalar_type.warehouse_table_options).to eq({precision: 10, scale: 2})
  end

  it "converts scalar type to warehouse field type" do
    require "elastic_graph/warehouse/schema_definition/api_extension"

    results = define_schema(schema_element_name_form: :snake_case, extension_modules: [ElasticGraph::Warehouse::SchemaDefinition::APIExtension]) do |s|
      s.json_schema_version 1

      s.scalar_type "UUID" do |t|
        t.mapping type: "keyword"
        t.json_schema type: "string", pattern: "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"
      end

      s.object_type "Entity" do |t|
        t.field "id", "UUID"
        t.warehouse_table "entities"
      end
    end

    scalar_type = results.state.scalar_types_by_name["UUID"]
    field_type = scalar_type.to_warehouse_field_type

    expect(field_type).to be_a(ElasticGraph::Warehouse::WarehouseConfig::FieldType::Scalar)
    expect(field_type.scalar_type).to eq(scalar_type)
  end

  it "handles built-in scalar types" do
    require "elastic_graph/warehouse/schema_definition/api_extension"

    results = define_schema(schema_element_name_form: :snake_case, extension_modules: [ElasticGraph::Warehouse::SchemaDefinition::APIExtension]) do |s|
      s.json_schema_version 1

      s.object_type "BasicTypes" do |t|
        t.field "string_field", "String"
        t.field "int_field", "Int"
        t.field "float_field", "Float"
        t.field "boolean_field", "Boolean"
        t.field "id_field", "ID"
        t.warehouse_table "basic_types"
      end
    end

    table = results.warehouse_config.fetch("basic_types")
    expect(table.fetch("table_schema")).to include("string_field STRING")
    expect(table.fetch("table_schema")).to include("int_field INT")
    expect(table.fetch("table_schema")).to include("float_field DOUBLE")
    expect(table.fetch("table_schema")).to include("boolean_field BOOLEAN")
    expect(table.fetch("table_schema")).to include("id_field STRING")
  end

  it "handles scalar types with warehouse_table_options[:type] set" do
    require "elastic_graph/warehouse/schema_definition/api_extension"

    results = define_schema(schema_element_name_form: :snake_case, extension_modules: [ElasticGraph::Warehouse::SchemaDefinition::APIExtension]) do |s|
      s.json_schema_version 1

      s.scalar_type "CustomType" do |t|
        t.mapping type: "keyword"
        t.json_schema type: "string"
        t.warehouse_table type: "BINARY"
      end

      s.object_type "TestType" do |t|
        t.field "custom", "CustomType"
        t.warehouse_table "test_types"
      end
    end

    table = results.warehouse_config.fetch("test_types")
    expect(table.fetch("table_schema")).to include("custom BINARY")
  end
end
