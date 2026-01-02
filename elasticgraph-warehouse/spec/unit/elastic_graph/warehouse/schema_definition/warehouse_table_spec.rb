# Copyright 2024 - 2026 Block, Inc.
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
        it "generates table schema with warehouse_table definition on index" do
          results = define_warehouse_schema do |s|
            s.object_type "Product" do |t|
              t.field "id", "ID"
              t.field "name", "String"
              t.field "price", "Float"
              t.index "products"
            end
          end

          product_type = results.state.object_types_by_name.fetch("Product")
          index = product_type.index_def
          table = index.warehouse_table_def

          expect(table).to be_a(WarehouseTable)
          expect(table.name).to eq("products")

          expect(table.index).to eq(index)
        end

        it "allows overriding warehouse_table name to differ from index name" do
          results = define_warehouse_schema do |s|
            s.object_type "Product" do |t|
              t.field "id", "ID"
              t.field "name", "String"
              t.index "products" do |i|
                i.warehouse_table "custom_products_table"
              end
            end
          end

          product_type = results.state.object_types_by_name.fetch("Product")
          table = product_type.index_def.warehouse_table_def

          expect(table).to be_a(WarehouseTable)
          expect(table.name).to eq("custom_products_table")
        end

        it "does not include excluded indices in warehouse config" do
          results = define_warehouse_schema do |s|
            s.object_type "Product" do |t|
              t.field "id", "ID"
              t.index "products"
              # This will automatically get a warehouse table
            end

            s.object_type "InternalMetrics" do |t|
              t.field "id", "ID"
              t.index "internal_metrics" do |i|
                i.exclude_from_warehouse
              end
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
              t.field "id", "ID"
              t.field "total", "Float"
              t.index "orders"
            end
          end

          order_type = results.state.object_types_by_name.fetch("Order")
          table = order_type.index_def.warehouse_table_def

          config = table.to_config
          expect(config).to have_key("table_schema")
          expect(config["table_schema"]).to eq(<<~SQL.strip)
            CREATE TABLE IF NOT EXISTS orders (
              id STRING,
              total FLOAT
            )
          SQL
        end

        it "generates complete CREATE TABLE SQL statement with all common scalar types" do
          results = define_warehouse_schema do |s|
            s.object_type "User" do |t|
              t.field "id", "ID"
              t.field "email", "String"
              t.field "age", "Int"
              t.field "is_active", "Boolean"
              t.index "users"
            end
          end

          user_type = results.state.object_types_by_name.fetch("User")
          table = user_type.index_def.warehouse_table_def

          table_schema = table.to_config["table_schema"]
          expect(table_schema).to eq(<<~SQL.strip)
            CREATE TABLE IF NOT EXISTS users (
              id STRING,
              email STRING,
              age INT,
              is_active BOOLEAN
            )
          SQL
        end

        it "uses name_in_index for column names instead of GraphQL field names" do
          results = define_warehouse_schema do |s|
            s.object_type "Payment" do |t|
              t.field "id", "ID"
              t.field "amount", "Int", name_in_index: "amount_cents"
              t.field "currencyCode", "String", name_in_index: "currency"
              t.index "payments"
            end
          end

          payment_type = results.state.object_types_by_name.fetch("Payment")
          table = payment_type.index_def.warehouse_table_def

          table_schema = table.to_config["table_schema"]
          expect(table_schema).to eq(<<~SQL.strip)
            CREATE TABLE IF NOT EXISTS payments (
              id STRING,
              amount_cents INT,
              currency STRING
            )
          SQL
        end
      end
    end
  end
end
