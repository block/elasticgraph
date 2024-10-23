# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/warehouse/warehouse_config/field_type/enum"

module ElasticGraph
  module Warehouse
    module SchemaDefinition
      # Extends {ElasticGraph::SchemaDefinition::SchemaElements::EnumType} to add warehouse field type conversion.
      module EnumTypeExtension
        # Converts this enum type to a warehouse field type
        #
        # @return [ElasticGraph::Warehouse::WarehouseConfig::FieldType::Enum]
        def to_warehouse_field_type
          ::ElasticGraph::Warehouse::WarehouseConfig::FieldType::Enum.new(enum_value_names: values_by_name.keys)
        end
      end
    end
  end
end
