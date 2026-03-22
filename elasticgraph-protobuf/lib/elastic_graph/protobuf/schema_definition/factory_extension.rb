# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/protobuf/schema_definition/enum_type_extension"
require "elastic_graph/protobuf/schema_definition/object_interface_and_union_extension"
require "elastic_graph/protobuf/schema_definition/results_extension"
require "elastic_graph/protobuf/schema_definition/scalar_type_extension"
require "elastic_graph/protobuf/schema_definition/schema_artifact_manager_extension"

module ElasticGraph
  module Protobuf
    module SchemaDefinition
      # Extension module applied to Factory to add proto support.
      module FactoryExtension
        # Creates a new enum type with proto extensions.
        #
        # @param name [String] enum type name
        # @yield [ElasticGraph::SchemaDefinition::SchemaElements::EnumType]
        # @return [ElasticGraph::SchemaDefinition::SchemaElements::EnumType]
        def new_enum_type(name)
          super(name) do |type|
            type.extend EnumTypeExtension
            yield type if block_given?
          end
        end

        # Creates a new interface type with proto extensions.
        #
        # @param name [String] interface type name
        # @yield [ElasticGraph::SchemaDefinition::SchemaElements::InterfaceType]
        # @return [ElasticGraph::SchemaDefinition::SchemaElements::InterfaceType]
        def new_interface_type(name)
          super(name) do |type|
            type.extend ObjectInterfaceAndUnionExtension
            yield type if block_given?
          end
        end

        # Creates a new object type with proto extensions.
        #
        # @param name [String] object type name
        # @yield [ElasticGraph::SchemaDefinition::SchemaElements::ObjectType]
        # @return [ElasticGraph::SchemaDefinition::SchemaElements::ObjectType]
        def new_object_type(name)
          super(name) do |type|
            type.extend ObjectInterfaceAndUnionExtension
            yield type if block_given?
          end
        end

        # Creates a new scalar type with proto extensions.
        #
        # @param name [String] scalar type name
        # @yield [ElasticGraph::SchemaDefinition::SchemaElements::ScalarType]
        # @return [ElasticGraph::SchemaDefinition::SchemaElements::ScalarType]
        def new_scalar_type(name)
          super(name) do |type|
            type.extend ScalarTypeExtension
            yield type if block_given?
          end
        end

        # Creates a new union type with proto extensions.
        #
        # @param name [String] union type name
        # @yield [ElasticGraph::SchemaDefinition::SchemaElements::UnionType]
        # @return [ElasticGraph::SchemaDefinition::SchemaElements::UnionType]
        def new_union_type(name)
          super(name) do |type|
            type.extend ObjectInterfaceAndUnionExtension
            yield type if block_given?
          end
        end

        # Creates a new results object and extends it with proto generation APIs.
        #
        # @return [ElasticGraph::SchemaDefinition::Results]
        def new_results
          super.tap do |results|
            results.extend ResultsExtension
          end
        end

        # Creates a new schema artifact manager and extends it with proto artifact support.
        #
        # @return [ElasticGraph::SchemaDefinition::SchemaArtifactManager]
        def new_schema_artifact_manager(...)
          super.tap do |manager|
            manager.extend SchemaArtifactManagerExtension
          end
        end
      end
    end
  end
end
