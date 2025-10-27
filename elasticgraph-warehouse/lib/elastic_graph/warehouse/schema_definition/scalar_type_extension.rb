# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  module Warehouse
    module SchemaDefinition
      # Extends {ElasticGraph::SchemaDefinition::SchemaElements::ScalarType} to add warehouse column type conversion.
      module ScalarTypeExtension
        # Warehouse column type configured on this scalar type.
        attr_reader :warehouse_column_type

        # Configures warehouse column type for this scalar type.
        #
        # @param type [String] the warehouse column type (e.g., "TIMESTAMP", "BINARY")
        # @return [String] the configured warehouse column type
        def warehouse_column(type:)
          @warehouse_column_type = type
        end

        # Returns the warehouse column type representation for this scalar type.
        #
        # @return [String] the SQL type string (e.g., "INT", "DOUBLE", "BOOLEAN", "STRING")
        # @raise [RuntimeError] if warehouse_column_type has not been configured
        # @note Built-in ElasticGraph scalar types are automatically configured with appropriate warehouse column types.
        #   Custom scalar types must explicitly call `warehouse_column` to specify their warehouse type.
        def to_warehouse_column_type
          warehouse_column_type || raise("Warehouse column type not configured for scalar type #{name.inspect}. " \
            "Call `warehouse_column type: \"TYPE\"` in the scalar type definition.")
        end
      end
    end
  end
end
