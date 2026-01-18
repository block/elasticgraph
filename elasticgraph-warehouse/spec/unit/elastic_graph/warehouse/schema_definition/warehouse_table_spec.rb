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
        it "generates complete CREATE TABLE SQL statement" do
          results = define_warehouse_schema do |s|
            s.object_type "User" do |t|
              t.field "id", "ID"
              t.field "email", "String"
              t.field "age", "Int"
              t.field "is_active", "Boolean"
              t.index "users"
            end
          end

          expect(table_schema_from(results, "users")).to eq(<<~SQL.strip)
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

          expect(table_schema_from(results, "payments")).to eq(<<~SQL.strip)
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
