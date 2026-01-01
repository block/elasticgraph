# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/warehouse/schema_definition/warehouse_table"

module ElasticGraph
  module Warehouse
    module SchemaDefinition
      # Extension module for {ElasticGraph::SchemaDefinition::Results} that adds warehouse configuration support.
      #
      # @private
      module ResultsExtension
        # Returns the warehouse configuration generated from the schema definition.
        #
        # @return [Hash<String, Hash>] a hash mapping table names to their configuration
        def warehouse_config
          @warehouse_config ||= generate_warehouse_config
        end

        private

        # Generates warehouse configuration from indices that have warehouse table definitions.
        #
        # @return [Hash<String, Hash>] a hash mapping table names to their configuration
        def generate_warehouse_config
          tables = all_types
            .filter_map { |type| (_ = type).index_def if type.respond_to?(:index_def) }
            .filter_map(&:warehouse_table_def)
            .sort_by(&:name)

          {"tables" => tables.to_h { |table| [table.name, table.to_config] }}
        end
      end
    end
  end
end
