# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/warehouse/patches"
require "elastic_graph/warehouse/schema_definition/factory_extension"
require "elastic_graph/warehouse/schema_definition/scalar_type_extension"
require "elastic_graph/warehouse/schema_definition/enum_type_extension"
require "elastic_graph/warehouse/schema_definition/object_type_extension"
require "elastic_graph/warehouse/schema_definition/interface_type_extension"

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
      #     tasks.schema_definition_extension_modules = [ElasticGraph::Warehouse::SchemaDefinition::APIExtension]
      #   end
      module APIExtension
        # Extends the API with warehouse functionality when this module is extended
        #
        # @param api [ElasticGraph::SchemaDefinition::API] the API instance to extend
        # @return [void]
        def self.extended(api)
          api.factory.extend FactoryExtension

          # Apply warehouse extensions to built-in types so they have to_warehouse_field_type method
          api.on_built_in_types do |type|
            case type
            when ::ElasticGraph::SchemaDefinition::SchemaElements::ScalarType
              type.extend ScalarTypeExtension
            when ::ElasticGraph::SchemaDefinition::SchemaElements::EnumType
              type.extend EnumTypeExtension
            when ::ElasticGraph::SchemaDefinition::SchemaElements::ObjectType
              type.extend ObjectTypeExtension
            when ::ElasticGraph::SchemaDefinition::SchemaElements::InterfaceType
              # :nocov: -- No built-in InterfaceTypes currently exist in ElasticGraph. This branch is here for
              # future-proofing in case built-in interface types are added. User-defined interface types are
              # extended via FactoryExtension instead.
              type.extend InterfaceTypeExtension
              # :nocov:
            else
              # Other types (e.g., UnionType, InputType) don't yet support warehouse configs
            end
          end
        end
      end
    end
  end
end
