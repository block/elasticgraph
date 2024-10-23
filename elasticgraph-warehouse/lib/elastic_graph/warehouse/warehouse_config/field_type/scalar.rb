# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/support/hash_util"

module ElasticGraph
  module Warehouse
    module WarehouseConfig
      module FieldType
        # @!parse class Scalar < ::Data; end
        # Represents a scalar field type in a warehouse table
        Scalar = ::Data.define(:scalar_type)

        # Represents a scalar field type in a warehouse table
        class Scalar < ::Data
          # Returns the warehouse table type representation for this scalar field
          #
          # @return [String] the SQL type string (e.g., "INT", "DOUBLE", "BOOLEAN", "STRING")
          def to_table_type
            warehouse_type = scalar_type.warehouse_table_options[:type]
            return warehouse_type if warehouse_type

            # Map common ElasticGraph scalar types to warehouse types
            case scalar_type.name
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
end
