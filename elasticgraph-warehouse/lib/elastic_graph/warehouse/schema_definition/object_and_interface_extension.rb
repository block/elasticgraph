# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/warehouse/warehouse_config/warehouse_table"

module ElasticGraph
  module Warehouse
    module SchemaDefinition
      # Extends {ElasticGraph::SchemaDefinition::SchemaElements::ObjectType} and
      # {ElasticGraph::SchemaDefinition::SchemaElements::InterfaceType} to add warehouse table definition support.
      module ObjectAndInterfaceExtension
        attr_reader :warehouse_table_def

        # Defines a warehouse table for this object or interface type.
        #
        # @param name [String] name of the warehouse table
        # @param settings [Hash] warehouse table settings
        # @return [void]
        def warehouse_table(name, **settings)
          @warehouse_table_def = ::ElasticGraph::Warehouse::WarehouseConfig::WarehouseTable.new(name, settings, schema_def_state, self)
        end

        # Returns the warehouse column type representation for this object or interface type.
        #
        # @return [String] a STRUCT SQL type containing all subfields
        def to_warehouse_column_type
          subfields = indexing_fields_by_name_in_index.values.map(&:to_indexing_field).compact

          inner = subfields.map do |subfield|
            type = subfield.type.unwrap_non_null
            if type.list?
              resolved = type.unwrap_list.unwrap_non_null.resolved
              if resolved&.respond_to?(:to_warehouse_column_type)
                "#{subfield.name} ARRAY<#{resolved.to_warehouse_column_type}>"
              else
                "#{subfield.name} ARRAY<STRING>"
              end
            elsif type.resolved.nil? || !type.resolved.respond_to?(:to_warehouse_column_type)
              "#{subfield.name} VARIANT"
            else
              "#{subfield.name} #{type.resolved.to_warehouse_column_type}"
            end
          end.join(", ")

          "STRUCT<#{inner}>"
        end
      end
    end
  end
end
