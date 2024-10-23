# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/warehouse/schema_definition/field_type_converter"
require "elastic_graph/warehouse/schema_definition/api_extension"

module ElasticGraph
  module Warehouse
    module SchemaDefinition
      RSpec.describe FieldTypeConverter, :warehouse_schema do
        it "converts a basic scalar type to warehouse column type" do
          results = define_warehouse_schema do |s|
            s.object_type "Product" do |t|
              t.field "name", "String"
            end
          end

          expect(convert_field_type(results, "Product", "name")).to eq "STRING"
        end

        it "wraps list types in ARRAY" do
          results = define_warehouse_schema do |s|
            s.object_type "Product" do |t|
              t.field "tags", "[String!]!"
            end
          end

          expect(convert_field_type(results, "Product", "tags")).to eq "ARRAY<STRING>"
        end

        it "handles nested arrays" do
          results = define_warehouse_schema do |s|
            s.object_type "Matrix" do |t|
              t.field "values", "[[Float!]!]!"
            end
          end

          expect(convert_field_type(results, "Matrix", "values")).to eq "ARRAY<ARRAY<DOUBLE>>"
        end

        it "unwraps non-null wrapper before checking if type is a list" do
          results = define_warehouse_schema do |s|
            s.object_type "User" do |t|
              t.field "email", "String!"
            end
          end

          expect(convert_field_type(results, "User", "email")).to eq "STRING"
        end

        it "converts enum types to STRING" do
          results = define_warehouse_schema do |s|
            s.enum_type "Status" do |t|
              t.value "ACTIVE"
              t.value "INACTIVE"
            end

            s.object_type "Account" do |t|
              t.field "status", "Status"
            end
          end

          expect(convert_field_type(results, "Account", "status")).to eq "STRING"
        end

        it "converts nested object types to STRUCT" do
          results = define_warehouse_schema do |s|
            s.object_type "Address" do |t|
              t.field "street", "String"
              t.field "city", "String"
            end

            s.object_type "User" do |t|
              t.field "address", "Address"
            end
          end

          expect(convert_field_type(results, "User", "address")).to eq "STRUCT<street STRING, city STRING>"
        end

        it "converts arrays of objects to ARRAY<STRUCT>" do
          results = define_warehouse_schema do |s|
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

          expect(convert_field_type(results, "Order", "items")).to eq "ARRAY<STRUCT<id STRING, quantity INT>>"
        end

        it "converts custom scalar types with warehouse_column configuration" do
          results = define_warehouse_schema do |s|
            s.scalar_type "CustomTimestamp" do |t|
              t.mapping type: "date"
              t.json_schema type: "string", format: "date-time"
              t.warehouse_column type: "TIMESTAMP"
            end

            s.object_type "Event" do |t|
              t.field "occurred_at", "CustomTimestamp"
            end
          end

          expect(convert_field_type(results, "Event", "occurred_at")).to eq "TIMESTAMP"
        end

        it "raises an error when the resolved type does not respond to :to_warehouse_column_type" do
          results = define_warehouse_schema(extension_modules: []) do |s|
            s.scalar_type "CustomType" do |t|
              t.mapping type: "keyword"
              t.json_schema type: "string"
            end

            s.object_type "Doc" do |t|
              t.field "custom_field", "CustomType"
            end
          end

          field_type = results
            .state
            .types_by_name
            .fetch("Doc")
            .indexing_fields_by_name_in_index
            .fetch("custom_field")
            .to_indexing_field
            .type

          expect {
            FieldTypeConverter.convert(field_type)
          }.to raise_error(ArgumentError, /Cannot convert type to warehouse column.*does not respond to :to_warehouse_column_type/)
        end

        it "raises an error when the resolved type is nil" do
          results = define_warehouse_schema do |s|
            # Create schema with no types
          end

          # Create a type reference to a non-existent type
          non_existent_type = results.state.type_ref("NonExistentType")

          expect {
            FieldTypeConverter.convert(non_existent_type)
          }.to raise_error(ArgumentError, /Cannot convert type to warehouse column.*does not respond to :to_warehouse_column_type/)
        end

        def convert_field_type(results, type, field)
          field_type = results
            .state
            .types_by_name
            .fetch(type)
            .indexing_fields_by_name_in_index
            .fetch(field)
            .to_indexing_field
            .type

          FieldTypeConverter.convert(field_type)
        end
      end
    end
  end
end
