# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/warehouse/warehouse_config/warehouse_table"
require "elastic_graph/warehouse/warehouse_config/field_type/object"

module ElasticGraph
  module Warehouse
    module SchemaDefinition
      # Extends {ElasticGraph::SchemaDefinition::SchemaElements::InterfaceType} to add warehouse table definition support.
      module InterfaceTypeExtension
        attr_reader :warehouse_table_def

        # Defines a warehouse table for this interface type
        #
        # @param name [String] name of the warehouse table
        # @param settings [Hash] warehouse table settings
        # @yield [WarehouseTable] the warehouse table for further customization
        # @return [void]
        def warehouse_table(name, **settings, &block)
          @warehouse_table_def = ::ElasticGraph::Warehouse::WarehouseConfig::WarehouseTable.new(name, settings, schema_def_state, self, &block)
        end

        # Converts this interface type to a warehouse field type
        #
        # @return [ElasticGraph::Warehouse::WarehouseConfig::FieldType::Object]
        def to_warehouse_field_type
          ::ElasticGraph::Warehouse::WarehouseConfig::FieldType::Object.new(
            type_name: name,
            subfields: indexing_fields_by_name_in_index.values.map(&:to_indexing_field).compact,
            mapping_options: mapping_options,
            json_schema_options: json_schema_options
          )
        end
      end
    end
  end
end
