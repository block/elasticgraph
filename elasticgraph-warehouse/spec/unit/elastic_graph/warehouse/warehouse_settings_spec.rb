# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

RSpec.describe "warehouse table settings", :unit do
  include ElasticGraph::SchemaDefinition::TestSupport

  it "supports custom settings" do
    require "elastic_graph/warehouse/schema_definition/api_extension"

    results = define_schema(schema_element_name_form: :snake_case, extension_modules: [ElasticGraph::Warehouse::SchemaDefinition::APIExtension]) do |s|
      s.json_schema_version 1
      s.object_type "Event" do |t|
        t.field "id", "ID"
        t.field "createdDate", "Date"
        t.warehouse_table "event", retention_days: 30
      end
    end

    table = results.warehouse_config.fetch("event")
    expect(table.fetch("settings")).to eq({retention_days: 30})
  end
end
