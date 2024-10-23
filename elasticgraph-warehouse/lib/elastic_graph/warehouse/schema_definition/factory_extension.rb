# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/warehouse/schema_definition/enum_type_extension"
require "elastic_graph/warehouse/schema_definition/interface_type_extension"
require "elastic_graph/warehouse/schema_definition/object_type_extension"
require "elastic_graph/warehouse/schema_definition/scalar_type_extension"

module ElasticGraph
  module Warehouse
    module SchemaDefinition
      # Extension module applied to `ElasticGraph::SchemaDefinition::Factory` to add warehouse field type support.
      #
      # @private
      module FactoryExtension
        # Creates a new enum type with warehouse extensions
        #
        # @param name [String] the name of the enum type
        # @yield [type] the newly created enum type
        # @return [ElasticGraph::SchemaDefinition::SchemaElements::EnumType] the created enum type
        def new_enum_type(name)
          super(name) do |type|
            type.extend EnumTypeExtension
            yield type
          end
        end

        # Creates a new interface type with warehouse extensions
        #
        # @param name [String] the name of the interface type
        # @yield [type] the newly created interface type
        # @return [ElasticGraph::SchemaDefinition::SchemaElements::InterfaceType] the created interface type
        def new_interface_type(name)
          super(name) do |type|
            type.extend InterfaceTypeExtension
            yield type
          end
        end

        # Creates a new object type with warehouse extensions
        #
        # @param name [String] the name of the object type
        # @yield [type] the newly created object type (optional)
        # @return [ElasticGraph::SchemaDefinition::SchemaElements::ObjectType] the created object type
        def new_object_type(name)
          super(name) do |type|
            type.extend ObjectTypeExtension
            yield type if block_given?
          end
        end

        # Creates a new scalar type with warehouse extensions
        #
        # @param name [String] the name of the scalar type
        # @yield [type] the newly created scalar type
        # @return [ElasticGraph::SchemaDefinition::SchemaElements::ScalarType] the created scalar type
        def new_scalar_type(name)
          super(name) do |type|
            type.extend ScalarTypeExtension
            yield type
          end
        end
      end
    end
  end
end
