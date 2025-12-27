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
        it "generates warehouse config for indices with warehouse_table definitions" do
          results = define_warehouse_schema do |s|
            s.object_type "Product" do |t|
              t.field "id", "ID"
              t.field "name", "String"
              t.field "price", "Float"
              t.index "products" do |i|
                i.warehouse_table "products"
              end
            end

            s.object_type "Order" do |t|
              t.field "id", "ID"
              t.field "total", "Float"
              t.index "orders" do |i|
                i.warehouse_table "orders"
              end
            end
          end

          config = results.warehouse_config

          expect(config).to eq({
            "tables" => {
              "orders" => {
                "table_schema" => <<~SQL.strip
                  CREATE TABLE IF NOT EXISTS orders (
                    id STRING,
                    total FLOAT
                  )
                SQL
              },
              "products" => {
                "table_schema" => <<~SQL.strip
                  CREATE TABLE IF NOT EXISTS products (
                    id STRING,
                    name STRING,
                    price FLOAT
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

        it "excludes indices without warehouse_table definitions" do
          results = define_warehouse_schema do |s|
            s.object_type "Product" do |t|
              t.field "id", "ID"
              t.field "name", "String"
              t.index "products" do |i|
                i.warehouse_table "products"
              end
            end

            s.object_type "Category" do |t|
              t.field "id", "ID"
              t.field "name", "String"
              t.index "categories"
              # No warehouse_table definition
            end
          end

          config = results.warehouse_config

          expect(config["tables"].keys).to contain_exactly("products")
        end

        it "sorts warehouse tables by name" do
          results = define_warehouse_schema do |s|
            s.object_type "Zebra" do |t|
              t.field "id", "ID"
              t.index "zebras" do |i|
                i.warehouse_table "zebras"
              end
            end

            s.object_type "Apple" do |t|
              t.field "id", "ID"
              t.index "apples" do |i|
                i.warehouse_table "apples"
              end
            end

            s.object_type "Mango" do |t|
              t.field "id", "ID"
              t.index "mangos" do |i|
                i.warehouse_table "mangos"
              end
            end
          end

          config = results.warehouse_config

          expect(config["tables"].keys).to eq(["apples", "mangos", "zebras"])
        end

        it "memoizes the warehouse config" do
          results = define_warehouse_schema do |s|
            s.object_type "Product" do |t|
              t.field "id", "ID"
              t.index "products" do |i|
                i.warehouse_table "products"
              end
            end
          end

          first_call = results.warehouse_config
          second_call = results.warehouse_config

          expect(first_call).to be(second_call)
        end
      end
    end
  end
end
