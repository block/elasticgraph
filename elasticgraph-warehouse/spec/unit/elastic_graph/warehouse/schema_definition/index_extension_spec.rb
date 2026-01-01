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
      RSpec.describe IndexExtension, :warehouse_schema do
        it "excludes the index from warehouse when exclude_from_warehouse is called" do
          results = define_warehouse_schema do |s|
            s.object_type "Product" do |t|
              t.field "id", "ID"
              t.index "products" do |i|
                i.exclude_from_warehouse
              end
            end
          end

          product_type = results.state.object_types_by_name.fetch("Product")
          index = product_type.index_def

          expect(index.warehouse_table_def).to be_nil
        end

        it "automatically creates a warehouse table with the index name when no warehouse table is explicitly defined" do
          results = define_warehouse_schema do |s|
            s.object_type "Product" do |t|
              t.field "id", "ID"
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

        it "allows overriding the warehouse table name on an index" do
          results = define_warehouse_schema do |s|
            s.object_type "Product" do |t|
              t.field "id", "ID"
              t.index "products" do |i|
                i.warehouse_table "products_warehouse"
              end
            end
          end

          product_type = results.state.object_types_by_name.fetch("Product")
          index = product_type.index_def
          table = index.warehouse_table_def

          expect(table).to be_a(WarehouseTable)
          expect(table.name).to eq("products_warehouse")
          expect(table.index).to eq(index)
        end

        it "overwrites the warehouse table when called multiple times" do
          results = define_warehouse_schema do |s|
            s.object_type "Product" do |t|
              t.field "id", "ID"
              t.index "products" do |i|
                i.warehouse_table "first_table"
                i.warehouse_table "second_table"
              end
            end
          end

          product_type = results.state.object_types_by_name.fetch("Product")
          table = product_type.index_def.warehouse_table_def

          expect(table.name).to eq("second_table")
        end

        it "uses last-write-wins when exclude_from_warehouse is called before warehouse_table" do
          results = define_warehouse_schema do |s|
            s.object_type "Product" do |t|
              t.field "id", "ID"
              t.index "products" do |i|
                i.exclude_from_warehouse
                i.warehouse_table "products_warehouse"
              end
            end
          end

          product_type = results.state.object_types_by_name.fetch("Product")
          table = product_type.index_def.warehouse_table_def

          expect(table).to be_a(WarehouseTable)
          expect(table.name).to eq("products_warehouse")
        end

        it "uses last-write-wins when warehouse_table is called before exclude_from_warehouse" do
          results = define_warehouse_schema do |s|
            s.object_type "Product" do |t|
              t.field "id", "ID"
              t.index "products" do |i|
                i.warehouse_table "products_warehouse"
                i.exclude_from_warehouse
              end
            end
          end

          product_type = results.state.object_types_by_name.fetch("Product")
          index = product_type.index_def

          expect(index.warehouse_table_def).to be_nil
        end

        it "works with interface types" do
          results = define_warehouse_schema do |s|
            s.interface_type "Identifiable" do |t|
              t.field "id", "ID"
              t.index "identifiables"
            end

            s.object_type "Widget" do |t|
              t.implements "Identifiable"
              t.field "id", "ID"
            end
          end

          interface_type = results.state.types_by_name.fetch("Identifiable")
          table = interface_type.index_def.warehouse_table_def

          expect(table).to be_a(WarehouseTable)
          expect(table.name).to eq("identifiables")
        end

        it "works with union types" do
          results = define_warehouse_schema do |s|
            s.object_type "Card" do |t|
              t.field "id", "ID"
            end

            s.object_type "BankAccount" do |t|
              t.field "id", "ID"
            end

            s.union_type "PaymentMethod" do |t|
              t.subtypes "Card", "BankAccount"
              t.index "payment_methods"
            end
          end

          union_type = results.state.types_by_name.fetch("PaymentMethod")
          table = union_type.index_def.warehouse_table_def

          expect(table).to be_a(WarehouseTable)
          expect(table.name).to eq("payment_methods")
        end
      end
    end
  end
end
