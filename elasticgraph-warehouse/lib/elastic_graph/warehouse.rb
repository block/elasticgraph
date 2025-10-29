# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  # Warehouse extension: adds Data Warehouse config generation to ElasticGraph.
  #
  # This gem follows the same extension pattern as elasticgraph-apollo, using factory extensions
  # to add warehouse capabilities to schema elements.
  #
  # @example Using the warehouse extension
  #   require "elastic_graph/warehouse/schema_definition/api_extension"
  #
  #   ElasticGraph::Local::RakeTasks.new(
  #     local_config_yaml: "config/settings/local.yaml",
  #     path_to_schema: "config/schema.rb"
  #   ) do |tasks|
  #     tasks.schema_definition_extension_modules = [
  #       ElasticGraph::Warehouse::SchemaDefinition::APIExtension
  #     ]
  #   end
  module Warehouse
    # The name of the generated data warehouse configuration file.
    DATA_WAREHOUSE_FILE = "data_warehouse.yaml"
  end
end
