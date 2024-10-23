# Copyright 2024 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/constants"
require "elastic_graph/schema_definition/indexing/update_target_factory"
require "elastic_graph/schema_definition/warehouse_config/warehouse_table"

module ElasticGraph
  module SchemaDefinition
    module Mixins
      # Provides APIs for defining warehouse table configuration
      module HasWarehouseTables
        attr_reader :warehouse_table_def

        def warehouse_table(name, **settings, &block)
          @warehouse_table_def = WarehouseConfig::WarehouseTable.new(name, settings, schema_def_state, self, &block)
        end
      end
    end
  end
end
