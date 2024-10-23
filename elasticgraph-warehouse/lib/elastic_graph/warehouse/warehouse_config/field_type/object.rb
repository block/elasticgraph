# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  module Warehouse
    module WarehouseConfig
      module FieldType
        # Accepts the same attributes as the core TypeWithSubfields#to_warehouse_field_type call
        # and renders nested field types for table generation.
        Object = ::Data.define(:type_name, :subfields, :mapping_options, :json_schema_options) do
          def to_table_type
            inner = subfields.map do |subfield|
              type = subfield.type.unwrap_non_null
              if type.list?
                resolved = type.unwrap_list.unwrap_non_null.resolved
                if resolved&.respond_to?(:to_warehouse_field_type)
                  "#{subfield.name} ARRAY<#{resolved.to_warehouse_field_type.to_table_type}>"
                else
                  "#{subfield.name} ARRAY<STRING>"
                end
              elsif type.resolved.nil? || !type.resolved.respond_to?(:to_warehouse_field_type)
                "#{subfield.name} VARIANT"
              else
                "#{subfield.name} #{type.resolved.to_warehouse_field_type.to_table_type}"
              end
            end.join(", ")

            "STRUCT<#{inner}>"
          end
        end
      end
    end
  end
end
