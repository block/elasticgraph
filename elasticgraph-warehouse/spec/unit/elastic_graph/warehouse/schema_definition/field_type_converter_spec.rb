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
      RSpec.describe FieldTypeConverter, :warehouse_schema do
        it "wraps list types in ARRAY" do
          results = define_warehouse_schema do |s|
            s.object_type "Product" do |t|
              t.field "id", "ID"
              t.field "tags", "[String!]!"
              t.index "products"
            end
          end

          expect(warehouse_column_def_from(results, "products", "tags")).to eq "tags ARRAY<STRING>"
        end

        it "handles nested arrays" do
          results = define_warehouse_schema do |s|
            s.object_type "Matrix" do |t|
              t.field "id", "ID"
              t.field "values", "[[Float!]!]!"
              t.index "matrices"
            end
          end

          expect(warehouse_column_def_from(results, "matrices", "values")).to eq "values ARRAY<ARRAY<FLOAT>>"
        end

        it "converts arrays of objects to ARRAY<STRUCT>" do
          results = define_warehouse_schema do |s|
            s.object_type "Item" do |t|
              t.field "id", "ID"
              t.field "quantity", "Int"
            end

            s.object_type "Order" do |t|
              t.field "id", "ID"
              t.field "items", "[Item!]!" do |f|
                f.mapping type: "nested"
              end
              t.index "orders"
            end
          end

          expect(warehouse_column_def_from(results, "orders", "items")).to eq "items ARRAY<STRUCT<id STRING, quantity INT>>"
        end

        it "converts arrays of union types to ARRAY<STRUCT> with __typename" do
          results = define_warehouse_schema do |s|
            s.object_type "Email" do |t|
              t.field "id", "ID"
              t.field "address", "String"
            end

            s.object_type "Phone" do |t|
              t.field "id", "ID"
              t.field "number", "String"
            end

            s.union_type "ContactInfo" do |t|
              t.subtypes "Email", "Phone"
            end

            s.object_type "User" do |t|
              t.field "id", "ID"
              t.field "contacts", "[ContactInfo!]!" do |f|
                f.mapping type: "nested"
              end
              t.index "users"
            end
          end

          expect(warehouse_column_def_from(results, "users", "contacts")).to eq "contacts ARRAY<STRUCT<id STRING, address STRING, number STRING, __typename STRING>>"
        end
      end
    end
  end
end
