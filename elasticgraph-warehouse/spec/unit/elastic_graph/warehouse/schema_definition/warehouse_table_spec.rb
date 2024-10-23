# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/schema_definition/test_support"
require "elastic_graph/warehouse/schema_definition/api_extension"

RSpec.describe ElasticGraph::Warehouse::SchemaDefinition::WarehouseTable, :unit do
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

  it "handles nested arrays" do
    require "elastic_graph/warehouse/schema_definition/api_extension"

    results = define_schema(
      schema_element_name_form: :snake_case,
      extension_modules: [ElasticGraph::Warehouse::SchemaDefinition::APIExtension]
    ) do |s|
      s.json_schema_version 1
      s.object_type "Matrix" do |t|
        t.field "data", "[[Float!]]"
        t.warehouse_table "matrix"
      end
    end

    table = results.warehouse_config.fetch("matrix")
    expect(table.fetch("table_schema")).to include("data ARRAY<ARRAY<DOUBLE>>")
  end

  it "handles deeply nested arrays" do
    require "elastic_graph/warehouse/schema_definition/api_extension"

    results = define_schema(
      schema_element_name_form: :snake_case,
      extension_modules: [ElasticGraph::Warehouse::SchemaDefinition::APIExtension]
    ) do |s|
      s.json_schema_version 1
      s.object_type "Tensor" do |t|
        t.field "values", "[[[Int!]]]"
        t.warehouse_table "tensor"
      end
    end

    table = results.warehouse_config.fetch("tensor")
    expect(table.fetch("table_schema")).to include("values ARRAY<ARRAY<ARRAY<INT>>>")
  end

  it "handles nested arrays of objects" do
    require "elastic_graph/warehouse/schema_definition/api_extension"

    results = define_schema(
      schema_element_name_form: :snake_case,
      extension_modules: [ElasticGraph::Warehouse::SchemaDefinition::APIExtension]
    ) do |s|
      s.json_schema_version 1
      s.object_type "Point" do |t|
        t.field "x", "Float"
        t.field "y", "Float"
      end

      s.object_type "Grid" do |t|
        t.field "points", "[[Point!]]" do |f|
          f.mapping type: "nested"
        end
        t.warehouse_table "grid"
      end
    end

    table = results.warehouse_config.fetch("grid")
    expect(table.fetch("table_schema")).to include("points ARRAY<ARRAY<STRUCT<x DOUBLE, y DOUBLE>>>")
  end
end
