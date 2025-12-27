# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/warehouse/schema_definition/enum_type_extension"
require "elastic_graph/warehouse/schema_definition/index_extension"
require "elastic_graph/warehouse/schema_definition/object_interface_and_union_extension"
require "elastic_graph/warehouse/schema_definition/results_extension"
require "elastic_graph/warehouse/schema_definition/scalar_type_extension"

module ElasticGraph
  module Warehouse
    module SchemaDefinition
      # Extension module applied to `ElasticGraph::SchemaDefinition::Factory` to add warehouse field type support.
      #
      # @api private
      module FactoryExtension
        # Creates a new enum type with warehouse extensions.
        #
        # @param name [String] the name of the enum type
        # @yield [ElasticGraph::SchemaDefinition::SchemaElements::EnumType] the newly created enum type
        # @return [ElasticGraph::SchemaDefinition::SchemaElements::EnumType] the created enum type
        def new_enum_type(name)
          super(name) do |type|
            type.extend EnumTypeExtension
            # :nocov: -- currently all invocations have a block
            yield type if block_given?
            # :nocov:
          end
        end

        # Creates a new index with warehouse extensions.
        #
        # @param name [String] the name of the index
        # @param settings [Hash] additional settings for the index
        # @param type [Object] the type this index is for
        # @yield [ElasticGraph::SchemaDefinition::Indexing::Index] the newly created index (optional)
        # @return [ElasticGraph::SchemaDefinition::Indexing::Index] the created index
        def new_index(name, settings, type, &block)
          super(name, settings, type) do |index|
            index.extend IndexExtension
            block&.call(index)
          end
        end

        # Creates a new interface type with warehouse extensions.
        #
        # @param name [String] the name of the interface type
        # @yield [ElasticGraph::SchemaDefinition::SchemaElements::InterfaceType] the newly created interface type
        # @return [ElasticGraph::SchemaDefinition::SchemaElements::InterfaceType] the created interface type
        def new_interface_type(name)
          super(name) do |type|
            type.extend ObjectInterfaceAndUnionExtension
            # :nocov: -- currently all invocations have a block
            yield type if block_given?
            # :nocov:
          end
        end

        # Creates a new object type with warehouse extensions.
        #
        # @param name [String] the name of the object type
        # @yield [ElasticGraph::SchemaDefinition::SchemaElements::ObjectType] the newly created object type (optional)
        # @return [ElasticGraph::SchemaDefinition::SchemaElements::ObjectType] the created object type
        def new_object_type(name)
          super(name) do |type|
            type.extend ObjectInterfaceAndUnionExtension
            # :nocov: -- currently all invocations have a block
            yield type if block_given?
            # :nocov:
          end
        end

        # Creates a new scalar type with warehouse extensions.
        #
        # @param name [String] the name of the scalar type
        # @yield [ElasticGraph::SchemaDefinition::SchemaElements::ScalarType] the newly created scalar type
        # @return [ElasticGraph::SchemaDefinition::SchemaElements::ScalarType] the created scalar type
        def new_scalar_type(name)
          super(name) do |type|
            type.extend ScalarTypeExtension
            # :nocov: -- currently all invocations have a block
            yield type if block_given?
            # :nocov:
          end
        end

        # Creates a new union type with warehouse extensions.
        #
        # @param name [String] the name of the union type
        # @yield [ElasticGraph::SchemaDefinition::SchemaElements::UnionType] the newly created union type
        # @return [ElasticGraph::SchemaDefinition::SchemaElements::UnionType] the created union type
        def new_union_type(name)
          super(name) do |type|
            type.extend ObjectInterfaceAndUnionExtension
            # :nocov: -- currently all invocations have a block
            yield type if block_given?
            # :nocov:
          end
        end

        # Creates a new Results instance with warehouse extensions.
        #
        # @return [ElasticGraph::SchemaDefinition::Results] the created results instance
        def new_results
          super.tap do |results|
            results.extend ResultsExtension
          end
        end
      end
    end
  end
end
