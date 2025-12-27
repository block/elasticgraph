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
            s.scalar_type "CustomTimestamp" do |t|
              t.mapping type: "date"
              t.json_schema type: "string", format: "date-time"
              t.warehouse_column type: "TIMESTAMP"
            end
          end

          # Verify the scalar type has warehouse column type configured
          expect(warehouse_column_type_for(results, "CustomTimestamp")).to eq "TIMESTAMP"
        end

        it "handles built-in scalar types" do
          results = define_warehouse_schema

          # Test the scalar types directly
          expect(warehouse_column_type_for(results, "Int")).to eq("INT")
          expect(warehouse_column_type_for(results, "Float")).to eq("FLOAT")
          expect(warehouse_column_type_for(results, "Boolean")).to eq("BOOLEAN")
          expect(warehouse_column_type_for(results, "String")).to eq("STRING")
          expect(warehouse_column_type_for(results, "ID")).to eq("STRING")
        end

        it "raises an error when a custom scalar type does not configure warehouse_column" do
          results = define_warehouse_schema do |s|
            s.scalar_type "UnconfiguredScalar" do |t|
              t.mapping type: "keyword"
              t.json_schema type: "string"
              # Intentionally NOT calling t.warehouse_column
            end
          end

          expect {
            warehouse_column_type_for(results, "UnconfiguredScalar")
          }.to raise_error(Errors::SchemaError, a_string_including(
            "Warehouse column type not configured for scalar type `UnconfiguredScalar`.",
            "call `warehouse_column type:"
          ))
        end
      end
    end
  end
end
