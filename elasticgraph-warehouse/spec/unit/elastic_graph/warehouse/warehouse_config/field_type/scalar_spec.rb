# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

RSpec.describe ElasticGraph::Warehouse::WarehouseConfig::FieldType::Scalar, :unit do
  include ElasticGraph::SchemaDefinition::TestSupport

  it "defaults to STRING for table type" do
    require "elastic_graph/warehouse/schema_definition/api_extension"

    results = define_schema(schema_element_name_form: :snake_case, extension_modules: [ElasticGraph::Warehouse::SchemaDefinition::APIExtension]) do |s|
      s.json_schema_version 1

      s.scalar_type "Foo" do |t|
        t.mapping type: "integer"
        t.json_schema type: "integer"
      end

      s.object_type "Thing" do |t|
        t.field "v", "Foo"
        t.warehouse_table "thing"
      end
    end

    table = results.warehouse_config.fetch("thing")
    expect(table.fetch("table_schema")).to match("v STRING")
  end

  it "respects scalar.warehouse_table(table_type:) override" do
    require "elastic_graph/warehouse/schema_definition/api_extension"

    results = define_schema(schema_element_name_form: :snake_case, extension_modules: [ElasticGraph::Warehouse::SchemaDefinition::APIExtension]) do |s|
      s.json_schema_version 1

      s.scalar_type "Tag" do |t|
        t.mapping type: "keyword"
        t.json_schema type: "string"
        t.warehouse_table table_type: "STRING"
      end

      s.object_type "Doc" do |t|
        t.field "tag", "Tag"
        t.warehouse_table "doc"
      end
    end

    table = results.warehouse_config.fetch("doc")
    expect(table.fetch("table_schema")).to match("tag STRING")
  end
end
