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

        it "automatically sets warehouse_table to match index name when index is called" do
          results = define_warehouse_schema do |s|
            s.object_type "Product" do |t|
              t.field "id", "ID"
              t.field "name", "String"
              t.index "products"
              # No explicit warehouse_table call - should be automatically set
            end
          end

          product_type = results.state.object_types_by_name.fetch("Product")
          table = product_type.warehouse_table_def

          expect(table).to be_a(WarehouseTable)
          expect(table.name).to eq("products")
        end

        it "allows overriding warehouse_table name to differ from index name" do
          results = define_warehouse_schema do |s|
            s.object_type "Product" do |t|
              t.field "id", "ID"
              t.field "name", "String"
              t.warehouse_table "custom_products_table"
              t.index "products"
            end
          end

          product_type = results.state.object_types_by_name.fetch("Product")
          table = product_type.warehouse_table_def

          expect(table).to be_a(WarehouseTable)
          expect(table.name).to eq("custom_products_table")
        end

        it "allows excluding an indexed type from the warehouse" do
          results = define_warehouse_schema do |s|
            s.object_type "InternalMetrics" do |t|
              t.field "id", "ID"
              t.field "metric_name", "String"
              t.index "internal_metrics"
              t.exclude_from_warehouse
            end
          end

          internal_type = results.state.object_types_by_name.fetch("InternalMetrics")

          # The warehouse_table_def should not be a WarehouseTable
          expect(internal_type.warehouse_table_def).to be_a(Symbol)
          expect(internal_type.warehouse_table_def).not_to be_a(WarehouseTable)
        end

        it "does not include excluded types in warehouse config" do
          results = define_warehouse_schema do |s|
            s.object_type "Product" do |t|
              t.field "id", "ID"
              t.index "products"
              # This will automatically get a warehouse table
            end

            s.object_type "InternalMetrics" do |t|
              t.field "id", "ID"
              t.index "internal_metrics"
              t.exclude_from_warehouse
            end
          end

          warehouse_config = results.warehouse_config
          table_names = warehouse_config["tables"].keys

          expect(table_names).to eq(["products"])
          expect(table_names).not_to include("internal_metrics")
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
