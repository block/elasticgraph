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
      # Extends {ElasticGraph::SchemaDefinition::Indexing::Index} to add warehouse table definition support.
      module IndexExtension
        # Returns the warehouse table definition for this index, if one has been defined via {#warehouse_table}.
        #
        # @return [WarehouseTable, nil] the warehouse table definition, or `nil` if none has been defined
        # @dynamic warehouse_table_def
        attr_reader :warehouse_table_def

        # Defines a warehouse table for this index with a custom name.
        #
        # By default, a warehouse table is automatically created with the same name as the index.
        # Use this method only when you need a different table name than the index name.
        # To exclude an index from the warehouse entirely, use {#exclude_from_warehouse} instead.
        #
        # @param name [String] name of the warehouse table
        # @return [void]
        #
        # @example Override the default warehouse table name
        #   ElasticGraph.define_schema do |schema|
        #     schema.object_type "Product" do |t|
        #       t.field "id", "ID"
        #       t.field "name", "String"
        #
        #       t.index "products" do |i|
        #         # Override to use a different table name than "products"
        #         i.warehouse_table "store_products"
        #       end
        #     end
        #   end
        def warehouse_table(name)
          @warehouse_table_def = WarehouseTable.new(name: name, index: self)
        end

        # Excludes this index from the data warehouse configuration.
        # This is useful when you have an index but don't want it to be included
        # in the data warehouse.
        #
        # @return [void]
        #
        # @example Exclude an internal/test index from the warehouse
        #   ElasticGraph.define_schema do |schema|
        #     schema.object_type "InternalMetrics" do |t|
        #       t.field "id", "ID"
        #
        #       t.index "internal_metrics" do |i|
        #         i.exclude_from_warehouse # This index won't be in the data warehouse
        #       end
        #     end
        #   end
        def exclude_from_warehouse
          @warehouse_table_def = nil
        end
      end
    end
  end
end
