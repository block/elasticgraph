# Copyright 2024 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  module SchemaDefinition
    module WarehouseConfig
      # Contains implementation logic for the different types of indexing fields.
      #
      # @api private
      module FieldType
        # @!parse class Enum < ::Data; end
        Enum = ::Data.define(:enum_value_names)

        # Responsible for the JSON schema and mapping of a {SchemaElements::EnumType}.
        #
        # @!attribute [r] enum_value_names
        #   @return [Array<String>] list of names of values in this enum type.
        #
        # @api private
        class Enum < ::Data
          def to_table_type
             "STRING"
          end

          def to_parquet_type
            "ENUM" #Handle enum type
          end
        end
      end
    end
  end
end
