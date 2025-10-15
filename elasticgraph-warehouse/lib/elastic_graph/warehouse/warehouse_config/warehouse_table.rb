# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  module Warehouse
    # Contains warehouse configuration classes.
    module WarehouseConfig
      # Represents a warehouse table configuration.
      class WarehouseTable < Struct.new(:name, :settings, :schema_def_state, :indexed_type)
        # Initializes a new warehouse table.
        #
        # @param name [String] the name of the warehouse table
        # @param settings [Hash] table-specific settings
        # @param schema_def_state [Object] the schema definition state
        # @param indexed_type [Object] the indexed type this table represents
        # @return [WarehouseTable] the initialized warehouse table
        def initialize(name, settings, schema_def_state, indexed_type)
          super
        end

        # Converts the warehouse table to a configuration hash.
        #
        # @return [Hash] configuration hash with settings and table_schema
        def to_config
          {
            "settings" => settings,
            "table_schema" => table_schema
          }
        end

        # Generates the SQL CREATE TABLE statement for this warehouse table.
        #
        # @return [String] SQL CREATE TABLE statement with all fields
        def table_schema
          fields = indexed_type
            .indexing_fields_by_name_in_index
            .values
            .map { |field| "  #{table_field(field)}" }
            .join(",\n")

          <<~SQL.strip
            CREATE TABLE IF NOT EXISTS #{name} (
            #{fields}
            )
          SQL
        end

        private

        def table_field(field)
          field_name = field.name
          field_type = field.type

          resolved_type = if field_type.list?
            field_type.unwrap_list.unwrap_non_null.resolved
          else
            field_type.unwrap_non_null.resolved
          end

          # Handle unresolved types gracefully.
          unless resolved_type&.respond_to?(:to_warehouse_column_type)
            return field_type.list? ? "#{field_name} ARRAY<STRING>" : "#{field_name} STRING"
          end

          warehouse_type = resolved_type.to_warehouse_column_type

          if field_type.list?
            "#{field_name} ARRAY<#{warehouse_type}>"
          else
            "#{field_name} #{warehouse_type}"
          end
        end
      end
    end
  end
end
