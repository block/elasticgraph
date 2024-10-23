# Copyright 2024 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/support/hash_util"

module ElasticGraph
  module SchemaDefinition
    module WarehouseConfig
      module FieldType
        # @!parse class Scalar < ::Data; end
        Scalar = ::Data.define(:scalar_type)

        # Responsible for the JSON schema and mapping of a {SchemaElements::ScalarType}.
        #
        # @!attribute [r] scalar_type
        #   @return [SchemaElements::ScalarType] the scalar type
        #
        # @api private
        class Scalar < ::Data

          # @return [Hash<String, ::Object>] the JSON schema for this scalar type.
          def to_table_type
            if scalar_type.warehouse_table_options[:table_type].nil?
              "STRING"
            else
              scalar_type.warehouse_table_options[:table_type]
            end
          end

          def to_parquet_type
            if (scalar_type.mapping_options[:type] == "keyword")
              "binary"
            else
              scalar_type.mapping_options[:type]
            end
          end
        end
      end
    end
  end
end
