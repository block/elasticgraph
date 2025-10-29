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
              s.object_type "Address" do |t|
                t.field "street", "String"
                t.field "city", "String"
                t.field "zip", "String"
              end
            end

            expect(warehouse_column_type_for(results, "Address")).to eq("STRUCT<street STRING, city STRING, zip STRING>")
          end

          it "handles nested object types" do
            results = define_warehouse_schema do |s|
              s.object_type "Venue" do |t|
                t.field "id", "ID"
                t.field "name", "String"
                t.field "location", "GeoLocation"
              end
            end

            expect(warehouse_column_type_for(results, "Venue")).to eq("STRUCT<id STRING, name STRING, location STRUCT<latitude DOUBLE, longitude DOUBLE>>")
          end
        end

        describe "interface types" do
          it "converts interface type to warehouse column type" do
            results = define_warehouse_schema do |s|
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

            expect(warehouse_column_type_for(results, "Identifiable")).to eq("STRUCT<id STRING, name STRING, price DOUBLE, __typename STRING>")
          end
        end
      end
    end
  end
end
