# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/json_ingestion/schema_definition/built_in_types_extension"
require "elastic_graph/json_ingestion/schema_definition/enum_type_extension"
require "elastic_graph/json_ingestion/schema_definition/field_extension"
require "elastic_graph/json_ingestion/schema_definition/indexing/index"
require "elastic_graph/json_ingestion/schema_definition/object_interface_extension"
require "elastic_graph/json_ingestion/schema_definition/results_extension"
require "elastic_graph/json_ingestion/schema_definition/scalar_type_extension"
require "elastic_graph/json_ingestion/schema_definition/schema_artifact_manager_extension"
require "elastic_graph/json_ingestion/schema_definition/union_type_extension"

module ElasticGraph
  module JSONIngestion
    module SchemaDefinition
      # Extension module applied to `ElasticGraph::SchemaDefinition::Factory` to wire up
      # JSON Schema support on Results and SchemaArtifactManager instances.
      #
      # @api private
      module FactoryExtension
        # @private
        def new_built_in_types(api)
          super(api).tap do |built_in_types|
            built_in_types.extend BuiltInTypesExtension
          end
        end

        # @private
        def new_enum_type(name)
          super(name) do |type|
            type.extend EnumTypeExtension
            yield type if block_given?
          end
        end

        # @private
        def new_field(**kwargs, &block)
          super(**kwargs) do |field|
            field.extend FieldExtension
            block&.call(field)
          end
        end

        # @private
        def new_index(name, settings, type, &block)
          super(name, settings, type) do |index|
            index.extend Indexing::IndexExtension
            block&.call(index)
          end
        end

        # @private
        def new_interface_type(name)
          super(name) do |type|
            type.extend ObjectInterfaceExtension
            yield type if block_given?
          end
        end

        # @private
        def new_object_type(name)
          super(name) do |type|
            type.extend ObjectInterfaceExtension
            yield type if block_given?
          end
        end

        # @private
        def new_scalar_type(name)
          super(name) do |type|
            type.extend ScalarTypeExtension
            if (built_in_json_schema_options = BuiltInTypesExtension.json_schema_options_for_scalar(name))
              type.json_schema(**built_in_json_schema_options)
            end
            yield type if block_given?
          end.tap(&:validate_json_schema_configuration!)
        end

        # @private
        def new_union_type(name)
          super(name) do |type|
            type.extend UnionTypeExtension
            yield type if block_given?
          end
        end

        # Creates a new Results instance with JSON Schema extensions.
        #
        # @return [ElasticGraph::SchemaDefinition::Results] the created results instance
        def new_results
          super.tap do |results|
            results.extend ResultsExtension
          end
        end

        # Creates a new SchemaArtifactManager instance with JSON Schema extensions.
        #
        # @return [ElasticGraph::SchemaDefinition::SchemaArtifactManager] the created artifact manager
        def new_schema_artifact_manager(...)
          super.tap do |manager|
            manager.extend SchemaArtifactManagerExtension
          end
        end
      end
    end
  end
end
