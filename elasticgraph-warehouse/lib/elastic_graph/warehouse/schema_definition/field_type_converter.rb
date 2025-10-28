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
      # Converts ElasticGraph field types to warehouse column types.
      class FieldTypeConverter
        # Converts a field type to a warehouse column type string.
        #
        # Handles both scalar and list types, unwrapping nullability and delegating to
        # the resolved type's `to_warehouse_column_type` method. Supports
        # nested arrays like `[[String!]]` which become `ARRAY<ARRAY<STRING>>`.
        #
        # @param field_type [Object] the field type to convert
        # @return [String] the warehouse column type (e.g., "STRING", "ARRAY<INT>", "ARRAY<ARRAY<DOUBLE>>")
        def self.convert(field_type)
          unwrapped_type = field_type.unwrap_non_null

          if unwrapped_type.list?
            "ARRAY<#{convert(unwrapped_type.unwrap_list)}>"
          else
            unwrapped_type.resolved.to_warehouse_column_type
          end
        end
      end
    end
  end
end
