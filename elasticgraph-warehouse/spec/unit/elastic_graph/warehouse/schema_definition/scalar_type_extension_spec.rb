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
      RSpec.describe ScalarTypeExtension, :warehouse_schema do
        it "maps built-in scalar types to warehouse column types" do
          results = define_warehouse_schema do |s|
            s.object_type "Widget" do |t|
              t.field "id", "ID"
              t.field "name", "String"
              t.field "quantity", "Int"
              t.field "price", "Float"
              t.field "active", "Boolean"
              t.index "widgets"
            end
          end

          expect(warehouse_column_def_from(results, "widgets", "id")).to eq "id STRING"
          expect(warehouse_column_def_from(results, "widgets", "name")).to eq "name STRING"
          expect(warehouse_column_def_from(results, "widgets", "quantity")).to eq "quantity INT"
          expect(warehouse_column_def_from(results, "widgets", "price")).to eq "price FLOAT"
          expect(warehouse_column_def_from(results, "widgets", "active")).to eq "active BOOLEAN"
        end

        it "uses custom warehouse_column type for custom scalars" do
          results = define_warehouse_schema do |s|
            s.scalar_type "CustomTimestamp" do |t|
              t.mapping type: "date"
              t.json_schema type: "string", format: "date-time"
              t.warehouse_column type: "TIMESTAMP"
            end

            s.object_type "Event" do |t|
              t.field "id", "ID"
              t.field "occurred_at", "CustomTimestamp"
              t.index "events"
            end
          end

          expect(warehouse_column_def_from(results, "events", "occurred_at")).to eq "occurred_at TIMESTAMP"
        end

        it "raises an error when a custom scalar type does not configure warehouse_column" do
          results = define_warehouse_schema do |s|
            s.scalar_type "UnconfiguredScalar" do |t|
              t.mapping type: "keyword"
              t.json_schema type: "string"
              # Intentionally NOT calling t.warehouse_column
            end

            s.object_type "Widget" do |t|
              t.field "id", "ID"
              t.field "value", "UnconfiguredScalar"
              t.index "widgets"
            end
          end

          expect {
            results.warehouse_config
          }.to raise_error(Errors::SchemaError, a_string_including(
            "Warehouse column type not configured for scalar type `UnconfiguredScalar`.",
            "call `warehouse_column type:"
          ))
        end

        it "respects warehouse_column configuration from custom cursor scalar overrides (e.g., PaginationCursor)" do
          results = define_warehouse_schema(type_name_overrides: {Cursor: "PaginationCursor"}) do |s|
            # Define a custom type that includes a PaginationCursor field so we can verify
            # the warehouse column type is configured correctly.
            s.object_type "CursorTest" do |t|
              t.field "id", "ID"
              t.field "cursor_value", "PaginationCursor"
              t.index "cursor_tests"
            end
          end

          # The PaginationCursor scalar is automatically registered in built_in_types.rb with
          # warehouse_column type: "STRING", and the warehouse callback respects that configuration.
          expect(warehouse_column_def_from(results, "cursor_tests", "cursor_value")).to eq "cursor_value STRING"
        end
      end
    end
  end
end
