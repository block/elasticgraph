# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

RSpec.describe ElasticGraph::Warehouse::WarehouseConfig::FieldType::Object, :unit do
  include ElasticGraph::SchemaDefinition::TestSupport

  it "formats nested types correctly for table" do
    require "elastic_graph/warehouse/schema_definition/api_extension"

    results = define_schema(schema_element_name_form: :snake_case, extension_modules: [ElasticGraph::Warehouse::SchemaDefinition::APIExtension]) do |s|
      s.json_schema_version 1

      s.object_type "Address" do |t|
        t.field "city", "String"
        t.field "zip", "String"
      end

      s.object_type "User" do |t|
        t.field "name", "String"
        t.field "address", "Address"
        t.warehouse_table "user"
      end
    end

    table = results.warehouse_config.fetch("user")
    expect(table.fetch("table_schema")).to match("address STRUCT<city STRING, zip STRING>")
  end

  it "handles nested lists of objects" do
    require "elastic_graph/warehouse/schema_definition/api_extension"

    results = define_schema(schema_element_name_form: :snake_case, extension_modules: [ElasticGraph::Warehouse::SchemaDefinition::APIExtension]) do |s|
      s.json_schema_version 1

      s.object_type "Tag" do |t|
        t.field "name", "String"
      end

      s.object_type "Post" do |t|
        t.field "title", "String"
        t.field "tags", "[Tag]"
        t.warehouse_table "post"
      end
    end

    table = results.warehouse_config.fetch("post")
    expect(table.fetch("table_schema")).to match("tags ARRAY<STRUCT<name STRING>>")
  end

  it "handles non-null nested objects" do
    require "elastic_graph/warehouse/schema_definition/api_extension"

    results = define_schema(schema_element_name_form: :snake_case, extension_modules: [ElasticGraph::Warehouse::SchemaDefinition::APIExtension]) do |s|
      s.json_schema_version 1

      s.object_type "Location" do |t|
        t.field "lat", "Float"
        t.field "lng", "Float"
      end

      s.object_type "Place" do |t|
        t.field "name", "String"
        t.field "location", "Location!"
        t.warehouse_table "place"
      end
    end

    table = results.warehouse_config.fetch("place")
    expect(table.fetch("table_schema")).to include("location STRUCT<")
  end

  it "handles unresolved types gracefully" do
    require "elastic_graph/warehouse/schema_definition/api_extension"

    results = define_schema(schema_element_name_form: :snake_case, extension_modules: [ElasticGraph::Warehouse::SchemaDefinition::APIExtension]) do |s|
      s.json_schema_version 1

      # Create a mock field with unresolved type
      s.object_type "TestType" do |t|
        t.field "id", "ID"
        t.field "data", "JsonSafeLong" # This is a built-in type that may not have warehouse_field_type
        t.warehouse_table "test_type"
      end
    end

    table = results.warehouse_config.fetch("test_type")
    # Should handle unresolved types with fallback
    expect(table.fetch("table_schema")).to include("test_type")
  end

  it "handles list fields with nil resolved types" do
    require "elastic_graph/warehouse/schema_definition/api_extension"

    # Create a mock subfield with nil resolved type for list
    mock_unwrapped = instance_double("UnwrappedType")
    allow(mock_unwrapped).to receive(:resolved).and_return(nil)
    allow(mock_unwrapped).to receive(:unwrap_non_null).and_return(mock_unwrapped)

    mock_type = instance_double("Type")
    allow(mock_type).to receive(:list?).and_return(true)
    allow(mock_type).to receive(:unwrap_non_null).and_return(mock_type)
    allow(mock_type).to receive(:unwrap_list).and_return(mock_unwrapped)

    mock_subfield = instance_double("Subfield")
    allow(mock_subfield).to receive(:name).and_return("items")
    allow(mock_subfield).to receive(:type).and_return(mock_type)

    field_type = ElasticGraph::Warehouse::WarehouseConfig::FieldType::Object.new(
      type_name: "TestObject",
      subfields: [mock_subfield],
      mapping_options: {},
      json_schema_options: {}
    )

    # Should return fallback for unresolved list type
    expect(field_type.to_table_type).to eq("STRUCT<items ARRAY<STRING>>")
  end

  it "handles list fields where resolved type does not respond to to_warehouse_field_type" do
    require "elastic_graph/warehouse/schema_definition/api_extension"

    # Create a mock resolved type that doesn't respond to to_warehouse_field_type
    mock_resolved = instance_double("ResolvedType")
    allow(mock_resolved).to receive(:respond_to?).with(:to_warehouse_field_type).and_return(false)

    mock_unwrapped = instance_double("UnwrappedType")
    allow(mock_unwrapped).to receive(:resolved).and_return(mock_resolved)
    allow(mock_unwrapped).to receive(:unwrap_non_null).and_return(mock_unwrapped)

    mock_type = instance_double("Type")
    allow(mock_type).to receive(:list?).and_return(true)
    allow(mock_type).to receive(:unwrap_non_null).and_return(mock_type)
    allow(mock_type).to receive(:unwrap_list).and_return(mock_unwrapped)

    mock_subfield = instance_double("Subfield")
    allow(mock_subfield).to receive(:name).and_return("items")
    allow(mock_subfield).to receive(:type).and_return(mock_type)

    field_type = ElasticGraph::Warehouse::WarehouseConfig::FieldType::Object.new(
      type_name: "TestObject",
      subfields: [mock_subfield],
      mapping_options: {},
      json_schema_options: {}
    )

    # Should return fallback for list type without warehouse_field_type method
    expect(field_type.to_table_type).to eq("STRUCT<items ARRAY<STRING>>")
  end

  it "handles nullable fields with unresolved types" do
    require "elastic_graph/warehouse/schema_definition/api_extension"

    # Create a mock subfield with nil resolved type for nullable field
    mock_type = instance_double("Type")
    allow(mock_type).to receive(:list?).and_return(false)
    allow(mock_type).to receive(:non_null?).and_return(false)
    allow(mock_type).to receive(:unwrap_non_null).and_return(mock_type)
    allow(mock_type).to receive(:resolved).and_return(nil)

    mock_subfield = instance_double("Subfield")
    allow(mock_subfield).to receive(:name).and_return("optional_field")
    allow(mock_subfield).to receive(:type).and_return(mock_type)

    field_type = ElasticGraph::Warehouse::WarehouseConfig::FieldType::Object.new(
      type_name: "TestObject",
      subfields: [mock_subfield],
      mapping_options: {},
      json_schema_options: {}
    )

    # Should return VARIANT for unresolved nullable type in table
    expect(field_type.to_table_type).to eq("STRUCT<optional_field VARIANT>")
  end

  it "handles non-null fields with unresolved types" do
    require "elastic_graph/warehouse/schema_definition/api_extension"

    # Create a mock subfield with nil resolved type for non-null field
    mock_type = instance_double("Type")
    allow(mock_type).to receive(:list?).and_return(false)
    allow(mock_type).to receive(:non_null?).and_return(true)
    allow(mock_type).to receive(:unwrap_non_null).and_return(mock_type)
    allow(mock_type).to receive(:resolved).and_return(nil)

    mock_subfield = instance_double("Subfield")
    allow(mock_subfield).to receive(:name).and_return("required_field")
    allow(mock_subfield).to receive(:type).and_return(mock_type)

    field_type = ElasticGraph::Warehouse::WarehouseConfig::FieldType::Object.new(
      type_name: "TestObject",
      subfields: [mock_subfield],
      mapping_options: {},
      json_schema_options: {}
    )

    # Should return VARIANT for unresolved non-null type in table
    expect(field_type.to_table_type).to eq("STRUCT<required_field VARIANT>")
  end

  it "handles fields where resolved type does not respond to to_warehouse_field_type" do
    require "elastic_graph/warehouse/schema_definition/api_extension"

    # Create a mock resolved type that doesn't respond to to_warehouse_field_type
    mock_resolved = instance_double("ResolvedType")
    allow(mock_resolved).to receive(:respond_to?).with(:to_warehouse_field_type).and_return(false)

    mock_type = instance_double("Type")
    allow(mock_type).to receive(:list?).and_return(false)
    allow(mock_type).to receive(:unwrap_non_null).and_return(mock_type)
    allow(mock_type).to receive(:resolved).and_return(mock_resolved)

    mock_subfield = instance_double("Subfield")
    allow(mock_subfield).to receive(:name).and_return("custom_field")
    allow(mock_subfield).to receive(:type).and_return(mock_type)

    field_type = ElasticGraph::Warehouse::WarehouseConfig::FieldType::Object.new(
      type_name: "TestObject",
      subfields: [mock_subfield],
      mapping_options: {},
      json_schema_options: {}
    )

    # Should return VARIANT for type without warehouse_field_type method
    expect(field_type.to_table_type).to eq("STRUCT<custom_field VARIANT>")
  end

  it "handles list fields with resolved types that have to_warehouse_field_type in table" do
    require "elastic_graph/warehouse/schema_definition/api_extension"

    # Create a mock resolved type that responds to to_warehouse_field_type
    mock_warehouse_field = instance_double("WarehouseFieldType")
    allow(mock_warehouse_field).to receive(:to_table_type).and_return("INT")

    mock_resolved = instance_double("ResolvedType")
    allow(mock_resolved).to receive(:respond_to?).with(:to_warehouse_field_type).and_return(true)
    allow(mock_resolved).to receive(:to_warehouse_field_type).and_return(mock_warehouse_field)

    mock_type = instance_double("Type")
    allow(mock_type).to receive(:list?).and_return(true)
    allow(mock_type).to receive(:unwrap_list).and_return(mock_type)
    allow(mock_type).to receive(:unwrap_non_null).and_return(mock_type)
    allow(mock_type).to receive(:resolved).and_return(mock_resolved)

    mock_subfield = instance_double("Subfield")
    allow(mock_subfield).to receive(:name).and_return("numbers")
    allow(mock_subfield).to receive(:type).and_return(mock_type)

    field_type = ElasticGraph::Warehouse::WarehouseConfig::FieldType::Object.new(
      type_name: "TestObject",
      subfields: [mock_subfield],
      mapping_options: {},
      json_schema_options: {}
    )

    # Should return ARRAY<INT> for list type in table
    expect(field_type.to_table_type).to eq("STRUCT<numbers ARRAY<INT>>")
  end
end
