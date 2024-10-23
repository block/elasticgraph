# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/warehouse/warehouse_config/field_type/scalar"

module ElasticGraph
  module Warehouse
    module SchemaDefinition
      # Extends {ElasticGraph::SchemaDefinition::SchemaElements::ScalarType} to add warehouse field type conversion.
      module ScalarTypeExtension
        # Warehouse table options configured on this scalar type
        def warehouse_table_options
          @warehouse_table_options ||= {}
        end

        # Configures warehouse table type options for this scalar type
        #
        # @param arg [Hash, nil] options hash or nil
        # @param options [Hash] additional options
        # @return [Hash] updated warehouse table options
        def warehouse_table(arg = nil, **options)
          opts = arg.is_a?(Hash) ? arg.merge(options) : options
          warehouse_table_options.update(opts)
        end

        # Converts this scalar type to a warehouse field type
        #
        # @return [ElasticGraph::Warehouse::WarehouseConfig::FieldType::Scalar]
        def to_warehouse_field_type
          ::ElasticGraph::Warehouse::WarehouseConfig::FieldType::Scalar.new(scalar_type: self)
        end
      end
    end
  end
end
