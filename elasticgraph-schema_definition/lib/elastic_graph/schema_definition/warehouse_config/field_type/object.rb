# Copyright 2024 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/errors"
require "elastic_graph/support/hash_util"
require "elastic_graph/support/memoizable_data"

module ElasticGraph
  module SchemaDefinition
    module WarehouseConfig
      module FieldType

        class Object < Support::MemoizableData.define(:type_name, :subfields, :mapping_options, :json_schema_options)
          def to_table_type
            subfieldTypes = subfields.map do |subfield|
              type = subfield.type.unwrap_non_null
              if type.list?
                "#{subfield.name}:ARRAY<#{type.unwrap_list.unwrap_non_null.resolved.to_warehouse_field_type.to_table_type}>"
              elsif type.resolved.nil?
                "#{subfield.name}:VARIANT" #TODO UNDERSTAND WHY THESE DONT RESOLVE
              else
                "#{subfield.name}:#{type.resolved.to_warehouse_field_type.to_table_type}"
              end
            end.join(', ')
            "STRUCT<#{subfieldTypes}>"
          end

          def to_parquet_type
            results = subfields.map do |subfield|
              if subfield.type.resolved.nil?
                "#{subfield.name} unknown" #TODO
              else
                "#{subfield.name}  #{subfield.type.resolved.to_warehouse_field_type.to_parquet_type};"
              end
            end

            "{#{results.join(', ')}}"
          end
        end
      end
    end
  end
end
