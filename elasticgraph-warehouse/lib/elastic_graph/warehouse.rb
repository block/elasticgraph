# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

# Warehouse extension: adds Data Warehouse config generation to ElasticGraph.
# This gem follows the same extension pattern as elasticgraph-apollo, using factory extensions
# to add warehouse capabilities to schema elements.
#
# To use this extension, add it to your schema definition extension modules:
#
#   require "elastic_graph/warehouse/schema_definition/api_extension"
#
#   ElasticGraph::Local::RakeTasks.new(...) do |tasks|
#     tasks.schema_definition_extension_modules = [
#       ElasticGraph::Warehouse::SchemaDefinition::APIExtension
#     ]
#   end

module ElasticGraph
  module Warehouse
    # The name of the generated data warehouse configuration file.
    DATA_WAREHOUSE_FILE = "data_warehouse.yaml"
  end
end

require "elastic_graph/warehouse/patches"
