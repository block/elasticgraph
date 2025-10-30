# Copyright 2024 - 2025 Block, Inc.
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

        # Generates warehouse configuration from object types that have warehouse table definitions.
        #
        # @return [Hash<String, Hash>] a hash mapping table names to their configuration
        def generate_warehouse_config
          # Ensure all_types is called first to trigger on_built_in_types callbacks
          # which configure warehouse column types for built-in scalar types
          all_types

          tables = state.object_types_by_name.values
            .select { |t| t.respond_to?(:warehouse_table_def) }
            .filter_map(&:warehouse_table_def)
            .sort_by(&:name)
          tables.to_h { |i| [i.name, i.to_config] }
        end
      end
    end
  end
end
