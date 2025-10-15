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
        # Warehouse column options configured on this scalar type.
        def warehouse_column_options
          @warehouse_column_options ||= {}
        end

        # Configures warehouse column type options for this scalar type.
        #
        # @param type [String] the warehouse column type (e.g., "TIMESTAMP", "BINARY")
        # @param options [Hash] additional options
        # @return [Hash] updated warehouse column options
        def warehouse_column(type:, **options)
          warehouse_column_options.update(options.merge(type: type))
        end

        # Returns the warehouse column type representation for this scalar type.
        #
        # @return [String] the SQL type string (e.g., "INT", "DOUBLE", "BOOLEAN", "STRING")
        def to_warehouse_column_type
          warehouse_type = warehouse_column_options[:type]
          return warehouse_type if warehouse_type

          # Map common ElasticGraph scalar types to warehouse types.
          case name
          when "Int"
            "INT"
          when "Float"
            "DOUBLE"
          when "Boolean"
            "BOOLEAN"
          else
            "STRING"
          end
        end
      end
    end
  end
end
