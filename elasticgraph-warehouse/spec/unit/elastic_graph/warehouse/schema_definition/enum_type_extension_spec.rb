# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/warehouse/schema_definition/api_extension"

module ElasticGraph
  module Warehouse
    module SchemaDefinition
      RSpec.describe EnumTypeExtension, :warehouse_schema do
        it "converts enum type to warehouse column type" do
          results = define_warehouse_schema do |s|
            s.json_schema_version 1

            s.enum_type "Status" do |t|
              t.value "ACTIVE"
              t.value "INACTIVE"
              t.value "PENDING"
            end
          end

          enum_type = results.state.enum_types_by_name["Status"]
          table_type = enum_type.to_warehouse_column_type

          expect(table_type).to eq("STRING")
        end

        it "handles enum types with many values" do
          results = define_warehouse_schema do |s|
            s.json_schema_version 1

            s.enum_type "Country" do |t|
              t.value "USA"
              t.value "CANADA"
              t.value "MEXICO"
              t.value "UK"
              t.value "FRANCE"
              t.value "GERMANY"
            end
          end

          enum_type = results.state.enum_types_by_name["Country"]
          table_type = enum_type.to_warehouse_column_type

          expect(table_type).to eq("STRING")
        end
      end
    end
  end
end
