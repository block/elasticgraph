# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/warehouse/warehouse_config/field_type_converter"

module ElasticGraph
  module Warehouse
    module SchemaDefinition
      # Extends {ElasticGraph::SchemaDefinition::SchemaElements::ObjectType} and
      # {ElasticGraph::SchemaDefinition::SchemaElements::InterfaceType} to add warehouse column type conversion.
      module ObjectAndInterfaceExtension
        # Returns the warehouse column type representation for this object or interface type.
        #
        # @return [String] a STRUCT SQL type containing all subfields
        def to_warehouse_column_type
          subfields = indexing_fields_by_name_in_index.values.map(&:to_indexing_field).compact

          struct_field_expressions = subfields.map do |subfield|
            warehouse_type = WarehouseConfig::FieldTypeConverter.convert(subfield.type)
            "#{subfield.name} #{warehouse_type}"
          end.join(", ")

          "STRUCT<#{struct_field_expressions}>"
        end
      end
    end
  end
end
