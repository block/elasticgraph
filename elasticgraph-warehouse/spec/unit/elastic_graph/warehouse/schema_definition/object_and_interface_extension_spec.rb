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
      RSpec.describe ObjectAndInterfaceExtension, :warehouse_schema do
        describe "object types" do
          it "converts object type to warehouse column type" do
            results = define_warehouse_schema do |s|
              s.json_schema_version 1

              s.object_type "Address" do |t|
                t.field "street", "String"
                t.field "city", "String"
                t.field "zip", "String"
              end
            end

            # Ensure on_built_in_types callbacks are executed before accessing types
            results.send(:all_types)

            object_type = results.state.object_types_by_name["Address"]
            table_type = object_type.to_warehouse_column_type

            expect(table_type).to be_a(String)
            expect(table_type).to start_with("STRUCT<")
            expect(table_type).to include("street STRING", "city STRING", "zip STRING")
          end

          it "handles nested object types" do
            results = define_warehouse_schema do |s|
              s.json_schema_version 1

              s.object_type "Location" do |t|
                t.field "lat", "Float"
                t.field "lng", "Float"
              end

              s.object_type "Venue" do |t|
                t.field "id", "ID"
                t.field "name", "String"
                t.field "location", "Location"
              end
            end

            # Ensure on_built_in_types callbacks are executed before accessing types
            results.send(:all_types)

            venue_type = results.state.object_types_by_name["Venue"]
            table_type = venue_type.to_warehouse_column_type

            expect(table_type).to be_a(String)
            expect(table_type).to start_with("STRUCT<")
            expect(table_type).to include("location STRUCT<lat DOUBLE, lng DOUBLE>")
          end
        end

        describe "interface types" do
          it "converts interface type to warehouse column type" do
            results = define_warehouse_schema do |s|
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
              end
            end

            # Ensure on_built_in_types callbacks are executed before accessing types
            results.send(:all_types)

            interface_type = results.state.types_by_name["Identifiable"]
            table_type = interface_type.to_warehouse_column_type

            expect(table_type).to be_a(String)
            expect(table_type).to start_with("STRUCT<")
            expect(table_type).to include("id STRING", "name STRING", "__typename STRING")
          end
        end
      end
    end
  end
end
