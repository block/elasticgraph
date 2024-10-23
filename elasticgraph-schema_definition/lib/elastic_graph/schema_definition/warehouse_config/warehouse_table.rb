# Copyright 2024 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#

module ElasticGraph
  module SchemaDefinition
    module WarehouseConfig
      class WarehouseTable < Struct.new(:name, :settings, :schema_def_state, :indexed_type)
        def to_config
          {
            "create_table_command" => create_table_command,
            "parquet_definition" => parquet_schema,
          }
        end

        def parquet_schema
          fields = indexed_type.indexing_fields_by_name_in_index.map do |name, field|
            if field.type.resolved.nil?
              "#{name} unknown;"
            elsif field.type.leaf?
              "#{name}  #{field.type.resolved.to_warehouse_field_type.to_parquet_type};"
            else
              "optional group #{name}  #{field.type.resolved.to_warehouse_field_type.to_parquet_type};"
            end
          end
          "message #{name} {\n#{fields.join("\n  ")}\n}\n"
        end

        def create_table_command
          fields = indexed_type.indexing_fields_by_name_in_index.map do |name, field|
            type = field.type.unwrap_non_null
            if type.list?
              "#{name} ARRAY<#{type.unwrap_list.unwrap_non_null.resolved.to_warehouse_field_type.to_table_type}>"
            elsif type.resolved.nil?
              "#{name} VARIANT" #TODO UNDERSTAND WHY THESE DONT RESOLVE
            else
              "#{name} #{type.resolved.to_warehouse_field_type.to_table_type}"
            end
          end
          "CREATE TABLE IF NOT EXISTS #{name} (#{fields.join(",\n  ")});"
        end
      end
    end
  end
end
