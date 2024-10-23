# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

RSpec.describe ElasticGraph::Warehouse::WarehouseConfig::FieldType::Enum, :unit do
  include ElasticGraph::SchemaDefinition::TestSupport

  it "maps enum types to STRING for table" do
    require "elastic_graph/warehouse/schema_definition/api_extension"

    results = define_schema(schema_element_name_form: :snake_case, extension_modules: [ElasticGraph::Warehouse::SchemaDefinition::APIExtension]) do |s|
      s.json_schema_version 1

      s.enum_type "Color" do |t|
        t.values "RED", "GREEN", "YELLOW"
      end

      s.object_type "Thing" do |t|
        t.field "color", "Color"
        t.warehouse_table "thing"
      end
    end

    table = results.warehouse_config.fetch("thing")
    expect(table.fetch("table_schema")).to match("color STRING")
  end
end
