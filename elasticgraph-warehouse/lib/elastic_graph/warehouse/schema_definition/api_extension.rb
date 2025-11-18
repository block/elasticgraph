# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/warehouse/schema_definition/factory_extension"
require "elastic_graph/warehouse/schema_definition/scalar_type_extension"
require "elastic_graph/warehouse/schema_definition/enum_type_extension"
require "elastic_graph/warehouse/schema_definition/object_interface_and_union_extension"

module ElasticGraph
  module Warehouse
    # Namespace for all Warehouse schema definition support.
    #
    # {SchemaDefinition::APIExtension} is the primary entry point and should be used as a schema definition extension module.
    module SchemaDefinition
      # Module designed to be extended onto an {ElasticGraph::SchemaDefinition::API} instance
      # to add Data Warehouse configuration generation capabilities.
      #
      # To use this module, pass it in `schema_definition_extension_modules` when defining your {ElasticGraph::Local::RakeTasks}.
      #
      # @example Define local rake tasks with this extension module
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
      module APIExtension
        # Maps built-in ElasticGraph scalar types to their warehouse column types.
        COLUMN_TYPES_BY_BUILT_IN_SCALAR_TYPE = {
          "Boolean" => "BOOLEAN",
          "Cursor" => "STRING",
          "Date" => "DATE",
          "DateTime" => "TIMESTAMP",
          "Float" => "DOUBLE",
          "ID" => "STRING",
          "Int" => "INT",
          "JsonSafeLong" => "BIGINT",
          "LocalTime" => "STRING",
          "LongString" => "BIGINT",
          "String" => "STRING",
          "TimeZone" => "STRING",
          "Untyped" => "STRING"
        }.freeze

        # Extends the API with warehouse functionality when this module is extended.
        #
        # @param api [ElasticGraph::SchemaDefinition::API] the API instance to extend
        # @return [void]
        # @api private
        def self.extended(api)
          api.factory.extend FactoryExtension

          api.on_built_in_types do |type|
            case type
            when ScalarTypeExtension
              type.warehouse_column type: COLUMN_TYPES_BY_BUILT_IN_SCALAR_TYPE.fetch(type.name)
            end
          end
        end
      end
    end
  end
end
