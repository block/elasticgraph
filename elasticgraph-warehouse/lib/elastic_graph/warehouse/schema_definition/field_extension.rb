# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  module Warehouse
    module SchemaDefinition
      # Extends {ElasticGraph::SchemaDefinition::SchemaElements::Field} to support custom warehouse column names.
      #
      # By default, warehouse tables use the field's `name_in_index` as the column name. This extension
      # allows overriding that on a per-field basis using {#warehouse_column_name}.
      #
      # @example Override the warehouse column name
      #   ElasticGraph.define_schema do |schema|
      #     schema.object_type "Widget" do |t|
      #       t.field "workspace_id", "ID", name_in_index: "workspace_id2" do |f|
      #         f.warehouse_column_name name: "workspace_id"
      #       end
      #       t.index "widgets"
      #     end
      #   end
      module FieldExtension
        # Returns the warehouse column name to use for this field.
        # Falls back to {ElasticGraph::SchemaDefinition::SchemaElements::Field#name_in_index} if no custom warehouse name has been configured.
        #
        # @return [String] the warehouse column name
        def name_for_warehouse
          @warehouse_column_name || name_in_index
        end

        # Configures a custom warehouse column name for this field.
        # When set, this name will be used in the generated `CREATE TABLE` statement
        # instead of the field's `name_in_index`.
        #
        # @param name [String] the warehouse column name
        # @return [void]
        def warehouse_column_name(name:)
          @warehouse_column_name = name
        end
      end
    end
  end
end
