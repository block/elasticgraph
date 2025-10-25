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
      # Extends {ElasticGraph::SchemaDefinition::SchemaElements::EnumType} to add warehouse column type conversion.
      module EnumTypeExtension
        # Returns the warehouse column type representation for this enum type.
        #
        # @return [String] the SQL type string "STRING"
        def to_warehouse_column_type
          "STRING"
        end
      end
    end
  end
end
