# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  # Namespace for warehouse-related functionality
  module Warehouse
    # Contains warehouse configuration classes
    module WarehouseConfig
      # Contains field type implementations for warehouse tables
      module FieldType
        # @!parse class Enum < ::Data; end
        # Represents an enum field type in a warehouse table
        Enum = ::Data.define(:enum_value_names)

        # Represents an enum field type in a warehouse table
        class Enum < ::Data
          # Returns the warehouse table type representation for this enum field
          #
          # @return [String] the SQL type string "STRING"
          def to_table_type
            "STRING"
          end
        end
      end
    end
  end
end
