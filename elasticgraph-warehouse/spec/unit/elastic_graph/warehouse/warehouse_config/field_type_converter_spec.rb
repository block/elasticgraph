# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/warehouse/warehouse_config/field_type_converter"
require "elastic_graph/warehouse/schema_definition/api_extension"

module ElasticGraph
  module Warehouse
    module WarehouseConfig
      RSpec.describe FieldTypeConverter, :warehouse_schema do
        it "converts a basic scalar type to warehouse column type" do
          results = define_warehouse_schema do |s|
            s.json_schema_version 1

            s.object_type "Product" do |t|
              t.field "name", "String"
            end
          end

          # Ensure built-in types are configured
          results.send(:all_types)

          product = results.state.object_types_by_name.fetch("Product")
          name_field = product.indexing_fields_by_name_in_index.fetch("name").to_indexing_field

          warehouse_type = FieldTypeConverter.convert(name_field.type)
          expect(warehouse_type).to eq("STRING")
        end

        it "wraps list types in ARRAY" do
          results = define_warehouse_schema do |s|
            s.json_schema_version 1

            s.object_type "Product" do |t|
              t.field "tags", "[String!]!"
            end
          end

          # Ensure built-in types are configured
          results.send(:all_types)

          product = results.state.object_types_by_name.fetch("Product")
          tags_field = product.indexing_fields_by_name_in_index.fetch("tags").to_indexing_field

          warehouse_type = FieldTypeConverter.convert(tags_field.type)
          expect(warehouse_type).to eq("ARRAY<STRING>")
        end

        it "handles nested arrays" do
          results = define_warehouse_schema do |s|
            s.json_schema_version 1

            s.object_type "Matrix" do |t|
              t.field "values", "[[Float!]!]!"
            end
          end

          # Ensure built-in types are configured
          results.send(:all_types)

          matrix = results.state.object_types_by_name.fetch("Matrix")
          values_field = matrix.indexing_fields_by_name_in_index.fetch("values").to_indexing_field

          warehouse_type = FieldTypeConverter.convert(values_field.type)
          expect(warehouse_type).to eq("ARRAY<ARRAY<DOUBLE>>")
        end

        it "unwraps non-null wrapper before checking if type is a list" do
          results = define_warehouse_schema do |s|
            s.json_schema_version 1

            s.object_type "User" do |t|
              t.field "email", "String!"
            end
          end

          # Ensure built-in types are configured
          results.send(:all_types)

          user = results.state.object_types_by_name.fetch("User")
          email_field = user.indexing_fields_by_name_in_index.fetch("email").to_indexing_field

          warehouse_type = FieldTypeConverter.convert(email_field.type)
          expect(warehouse_type).to eq("STRING")
        end

        it "converts enum types to STRING" do
          results = define_warehouse_schema do |s|
            s.json_schema_version 1

            s.enum_type "Status" do |t|
              t.value "ACTIVE"
              t.value "INACTIVE"
            end

            s.object_type "Account" do |t|
              t.field "status", "Status"
            end
          end

          # Ensure built-in types are configured
          results.send(:all_types)

          account = results.state.object_types_by_name.fetch("Account")
          status_field = account.indexing_fields_by_name_in_index.fetch("status").to_indexing_field

          warehouse_type = FieldTypeConverter.convert(status_field.type)
          expect(warehouse_type).to eq("STRING")
        end

        it "converts nested object types to STRUCT" do
          results = define_warehouse_schema do |s|
            s.json_schema_version 1

            s.object_type "Address" do |t|
              t.field "street", "String"
              t.field "city", "String"
            end

            s.object_type "User" do |t|
              t.field "address", "Address"
            end
          end

          # Ensure built-in types are configured
          results.send(:all_types)

          user = results.state.object_types_by_name.fetch("User")
          address_field = user.indexing_fields_by_name_in_index.fetch("address").to_indexing_field

          warehouse_type = FieldTypeConverter.convert(address_field.type)
          expect(warehouse_type).to eq("STRUCT<street STRING, city STRING>")
        end

        it "converts arrays of objects to ARRAY<STRUCT>" do
          results = define_warehouse_schema do |s|
            s.json_schema_version 1

            s.object_type "Item" do |t|
              t.field "id", "ID"
              t.field "quantity", "Int"
            end

            s.object_type "Order" do |t|
              t.field "items", "[Item!]!" do |f|
                f.mapping type: "nested"
              end
            end
          end

          # Ensure built-in types are configured
          results.send(:all_types)

          order = results.state.object_types_by_name.fetch("Order")
          items_field = order.indexing_fields_by_name_in_index.fetch("items").to_indexing_field

          warehouse_type = FieldTypeConverter.convert(items_field.type)
          expect(warehouse_type).to eq("ARRAY<STRUCT<id STRING, quantity INT>>")
        end

        it "converts custom scalar types with warehouse_column configuration" do
          results = define_warehouse_schema do |s|
            s.json_schema_version 1

            s.scalar_type "CustomTimestamp" do |t|
              t.mapping type: "date"
              t.json_schema type: "string", format: "date-time"
              t.warehouse_column type: "TIMESTAMP"
            end

            s.object_type "Event" do |t|
              t.field "occurred_at", "CustomTimestamp"
            end
          end

          # Ensure built-in types are configured
          results.send(:all_types)

          event = results.state.object_types_by_name.fetch("Event")
          occurred_at_field = event.indexing_fields_by_name_in_index.fetch("occurred_at").to_indexing_field

          warehouse_type = FieldTypeConverter.convert(occurred_at_field.type)
          expect(warehouse_type).to eq("TIMESTAMP")
        end
      end
    end
  end
end
