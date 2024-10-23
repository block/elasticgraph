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
      RSpec.describe WarehouseTable, :warehouse_schema do
        it "generates table schema with warehouse_table definition" do
          results = define_warehouse_schema do |s|
            s.object_type "Product" do |t|
              t.field "id", "ID"
              t.field "name", "String"
              t.field "price", "Float"
              t.warehouse_table "products"
            end
          end

          product_type = results.state.object_types_by_name.fetch("Product")
          table = product_type.warehouse_table_def

          expect(table).to be_a(WarehouseTable)
          expect(table.name).to eq("products")

          expect(table.indexed_type).to eq(product_type)
        end

        it "converts table to configuration hash" do
          results = define_warehouse_schema do |s|
            s.object_type "Order" do |t|
              t.field "order_id", "ID"
              t.field "total", "Float"
              t.warehouse_table "orders"
            end
          end

          order_type = results.state.object_types_by_name.fetch("Order")
          table = order_type.warehouse_table_def

          config = table.to_config
          expect(config).to have_key("table_schema")
          expect(config["table_schema"]).to eq(<<~SQL.strip)
            CREATE TABLE IF NOT EXISTS orders (
              order_id STRING,
              total DOUBLE
            )
          SQL
        end

        it "generates complete CREATE TABLE SQL statement" do
          results = define_warehouse_schema do |s|
            s.object_type "User" do |t|
              t.field "user_id", "ID"
              t.field "email", "String"
              t.field "age", "Int"
              t.field "is_active", "Boolean"
              t.warehouse_table "users"
            end
          end

          user_type = results.state.object_types_by_name.fetch("User")
          table = user_type.warehouse_table_def

          table_schema = table.to_config["table_schema"]
          expect(table_schema).to eq(<<~SQL.strip)
            CREATE TABLE IF NOT EXISTS users (
              user_id STRING,
              email STRING,
              age INT,
              is_active BOOLEAN
            )
          SQL
        end
      end
    end
  end
end
