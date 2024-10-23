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
      RSpec.describe ResultsExtension, :warehouse_schema do
        it "generates warehouse config for types with warehouse_table definitions" do
          results = define_warehouse_schema do |s|
            s.object_type "Product" do |t|
              t.field "id", "ID"
              t.field "name", "String"
              t.field "price", "Float"
              t.warehouse_table "products"
            end

            s.object_type "Order" do |t|
              t.field "order_id", "ID"
              t.field "total", "Float"
              t.warehouse_table "orders"
            end
          end

          config = results.warehouse_config

          expect(config).to eq({
            "tables" => {
              "orders" => {
                "table_schema" => <<~SQL.strip
                  CREATE TABLE IF NOT EXISTS orders (
                    order_id STRING,
                    total DOUBLE
                  )
                SQL
              },
              "products" => {
                "table_schema" => <<~SQL.strip
                  CREATE TABLE IF NOT EXISTS products (
                    id STRING,
                    name STRING,
                    price DOUBLE
                  )
                SQL
              }
            }
          })
        end

        it "returns empty hash when no warehouse tables are defined" do
          results = define_warehouse_schema do |s|
            s.object_type "User" do |t|
              t.field "id", "ID"
              t.field "name", "String"
            end
          end

          config = results.warehouse_config

          expect(config).to eq({"tables" => {}})
        end

        it "excludes object types without warehouse_table definitions" do
          results = define_warehouse_schema do |s|
            s.object_type "Product" do |t|
              t.field "id", "ID"
              t.field "name", "String"
              t.warehouse_table "products"
            end

            s.object_type "Category" do |t|
              t.field "id", "ID"
              t.field "name", "String"
              # No warehouse_table definition
            end
          end

          config = results.warehouse_config

          expect(config["tables"].keys).to contain_exactly("products")
          expect(config["tables"]).not_to have_key("Category")
        end

        it "sorts warehouse tables by name" do
          results = define_warehouse_schema do |s|
            s.object_type "Zebra" do |t|
              t.field "id", "ID"
              t.warehouse_table "zebras"
            end

            s.object_type "Apple" do |t|
              t.field "id", "ID"
              t.warehouse_table "apples"
            end

            s.object_type "Middle" do |t|
              t.field "id", "ID"
              t.warehouse_table "middles"
            end
          end

          config = results.warehouse_config

          expect(config["tables"].keys).to eq(%w[apples middles zebras])
        end

        it "memoizes warehouse config after first generation" do
          results = define_warehouse_schema do |s|
            s.object_type "Product" do |t|
              t.field "id", "ID"
              t.warehouse_table "products"
            end
          end

          # Call twice and verify it returns the same object instance
          config1 = results.warehouse_config
          config2 = results.warehouse_config

          expect(config1).to be(config2)
        end

        it "includes all object types with warehouse_table in config" do
          results = define_warehouse_schema do |s|
            s.object_type "Product" do |t|
              t.field "id", "ID"
              t.field "name", "String"
              t.field "price", "Float"
              t.warehouse_table "products"
            end

            s.object_type "User" do |t|
              t.field "user_id", "ID"
              t.field "email", "String"
              t.warehouse_table "users"
            end

            s.object_type "Order" do |t|
              t.field "order_id", "ID"
              t.warehouse_table "orders"
            end
          end

          config = results.warehouse_config

          expect(config["tables"].keys.size).to eq(3)
          expect(config["tables"]).to have_key("products")
          expect(config["tables"]).to have_key("users")
          expect(config["tables"]).to have_key("orders")

          # Verify each config has the table_schema key
          config["tables"].each do |table_name, table_config|
            expect(table_config).to have_key("table_schema")
            expect(table_config["table_schema"]).to start_with("CREATE TABLE IF NOT EXISTS #{table_name}")
          end
        end

        it "includes indexing_only fields in warehouse table definition" do
          results = define_warehouse_schema do |s|
            s.object_type "Product" do |t|
              t.field "id", "ID"
              t.field "name", "String"
              t.field "internal_code", "String", indexing_only: true
              t.warehouse_table "products"
            end
          end

          config = results.warehouse_config
          table_schema = config["tables"]["products"]["table_schema"]

          expect(table_schema).to eq(<<~SQL.strip)
            CREATE TABLE IF NOT EXISTS products (
              id STRING,
              name STRING,
              internal_code STRING
            )
          SQL
        end

        it "omits graphql_only fields from warehouse table definition" do
          results = define_warehouse_schema do |s|
            s.object_type "Product" do |t|
              t.field "id", "ID"
              t.field "name", "String"
              t.field "computed_field", "String", graphql_only: true
              t.warehouse_table "products"
            end
          end

          config = results.warehouse_config
          table_schema = config["tables"]["products"]["table_schema"]

          expect(table_schema).to eq(<<~SQL.strip)
            CREATE TABLE IF NOT EXISTS products (
              id STRING,
              name STRING
            )
          SQL
        end

        it "respects name_in_index for warehouse table column names" do
          results = define_warehouse_schema do |s|
            s.object_type "Product" do |t|
              t.field "id", "ID"
              t.field "product_name", "String", name_in_index: "pname"
              t.warehouse_table "products"
            end
          end

          config = results.warehouse_config
          table_schema = config["tables"]["products"]["table_schema"]

          expect(table_schema).to eq(<<~SQL.strip)
            CREATE TABLE IF NOT EXISTS products (
              id STRING,
              pname STRING
            )
          SQL
        end
      end
    end
  end
end
