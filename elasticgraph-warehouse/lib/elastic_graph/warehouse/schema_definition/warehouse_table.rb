# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/warehouse/schema_definition/field_type_converter"

module ElasticGraph
  module Warehouse
    module SchemaDefinition
      # Represents a warehouse table configuration.
      class WarehouseTable < ::Data.define(:name, :indexed_type)
        # Converts the warehouse table to a configuration hash.
        #
        # @return [Hash] configuration hash with table_schema
        def to_config
          {
            "table_schema" => table_schema
          }
        end

        private

        # Generates the SQL CREATE TABLE statement for this warehouse table.
        #
        # @return [String] SQL CREATE TABLE statement with all fields
        def table_schema
          fields = indexed_type
            .indexing_fields_by_name_in_index
            .values
            .filter_map(&:to_indexing_field)
            .map { |field| table_field(field) }
            .join(",\n  ")

          <<~SQL.strip
            CREATE TABLE IF NOT EXISTS #{name} (
              #{fields}
            )
          SQL
        end

        def table_field(field)
          field_name = field.name_in_index
          warehouse_type = FieldTypeConverter.convert(field.type)
          "#{field_name} #{warehouse_type}"
        end
      end
    end
  end
end
