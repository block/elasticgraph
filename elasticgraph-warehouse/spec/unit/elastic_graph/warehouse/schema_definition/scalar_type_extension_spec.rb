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
      RSpec.describe ScalarTypeExtension, :warehouse_schema do
        it "allows configuring warehouse column type on scalar types" do
          results = define_warehouse_schema do |s|
            s.json_schema_version 1

            s.scalar_type "CustomTimestamp" do |t|
              t.mapping type: "date"
              t.json_schema type: "string", format: "date-time"
              t.warehouse_column type: "TIMESTAMP"
            end
          end

          # Verify the scalar type has warehouse column type configured
          scalar_type = results.state.scalar_types_by_name["CustomTimestamp"]
          expect(scalar_type.warehouse_column_type).to eq("TIMESTAMP")
        end

        it "converts scalar type to warehouse column type" do
          results = define_warehouse_schema do |s|
            s.json_schema_version 1

            s.scalar_type "UUID" do |t|
              t.mapping type: "keyword"
              t.json_schema type: "string", pattern: "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"
              t.warehouse_column type: "STRING"
            end
          end

          # Ensure on_built_in_types callbacks are executed before accessing scalar types
          results.send(:all_types)

          scalar_type = results.state.scalar_types_by_name["UUID"]
          table_type = scalar_type.to_warehouse_column_type

          expect(table_type).to eq("STRING")
        end

        it "handles built-in scalar types" do
          results = define_warehouse_schema do |s|
            s.json_schema_version 1
          end

          # Ensure on_built_in_types callbacks are executed before accessing scalar types
          results.send(:all_types)

          # Test the scalar types directly
          expect(results.state.scalar_types_by_name["Int"].to_warehouse_column_type).to eq("INT")
          expect(results.state.scalar_types_by_name["Float"].to_warehouse_column_type).to eq("DOUBLE")
          expect(results.state.scalar_types_by_name["Boolean"].to_warehouse_column_type).to eq("BOOLEAN")
          expect(results.state.scalar_types_by_name["String"].to_warehouse_column_type).to eq("STRING")
          expect(results.state.scalar_types_by_name["ID"].to_warehouse_column_type).to eq("STRING")
        end

        it "converts custom scalar type with warehouse_column to warehouse column type" do
          results = define_warehouse_schema do |s|
            s.json_schema_version 1

            s.scalar_type "CustomType" do |t|
              t.mapping type: "keyword"
              t.json_schema type: "string"
              t.warehouse_column type: "BINARY"
            end
          end

          # Ensure on_built_in_types callbacks are executed before accessing scalar types
          results.send(:all_types)

          scalar_type = results.state.scalar_types_by_name["CustomType"]
          expect(scalar_type.to_warehouse_column_type).to eq("BINARY")
        end

        it "raises an error when a custom scalar type does not configure warehouse_column" do
          results = define_warehouse_schema do |s|
            s.json_schema_version 1

            s.scalar_type "UnconfiguredScalar" do |t|
              t.mapping type: "keyword"
              t.json_schema type: "string"
              # Intentionally NOT calling t.warehouse_column
            end
          end

          # Ensure on_built_in_types callbacks are executed before accessing scalar types
          results.send(:all_types)

          scalar_type = results.state.scalar_types_by_name["UnconfiguredScalar"]

          expect {
            scalar_type.to_warehouse_column_type
          }.to raise_error(RuntimeError, /Warehouse column type not configured for scalar type "UnconfiguredScalar".*Call `warehouse_column type:/)
        end
      end
    end
  end
end
