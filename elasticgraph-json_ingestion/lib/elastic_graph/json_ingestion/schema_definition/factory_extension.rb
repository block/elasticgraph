# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/json_ingestion/schema_definition/indexing/index_extension"
require "elastic_graph/json_ingestion/schema_definition/results_extension"
require "elastic_graph/json_ingestion/schema_definition/schema_artifact_manager_extension"
require "elastic_graph/json_ingestion/schema_definition/schema_elements/enum_type_extension"
require "elastic_graph/json_ingestion/schema_definition/schema_elements/field_extension"
require "elastic_graph/json_ingestion/schema_definition/schema_elements/object_interface_extension"
require "elastic_graph/json_ingestion/schema_definition/schema_elements/scalar_type_extension"
require "elastic_graph/json_ingestion/schema_definition/schema_elements/type_reference_extension"

module ElasticGraph
  module JSONIngestion
    module SchemaDefinition
      # Extension module applied to `ElasticGraph::SchemaDefinition::Factory` to wire up
      # JSON Schema support on Results and SchemaArtifactManager instances.
      #
      # @api private
      module FactoryExtension
        # @private
        def new_enum_type(name)
          super(name) do |type|
            type.extend SchemaElements::EnumTypeExtension
            yield type if block_given?
          end
        end

        # @private
        def new_field(**kwargs, &block)
          super(**kwargs) do |field|
            field.extend SchemaElements::FieldExtension
            block&.call(field)
          end
        end

        # @private
        def new_index(name, settings, type, &block)
          super(name, settings, type) do |index|
            index.extend Indexing::IndexExtension
            index.require_id_in_json_schema
            block&.call(index)
          end
        end

        # @private
        def new_interface_type(name)
          super(name) do |type|
            type.extend SchemaElements::ObjectInterfaceExtension
            yield type if block_given?
          end
        end

        # @private
        def new_object_type(name)
          super(name) do |type|
            type.extend SchemaElements::ObjectInterfaceExtension
            yield type if block_given?
          end
        end

        # @private
        def new_scalar_type(name)
          super(name) do |type|
            type.extend SchemaElements::ScalarTypeExtension
            yield type if block_given?
            type.validate_json_schema_configuration! unless state.initially_registered_built_in_types.empty?
          end
        end

        # @private
        def new_type_reference(name)
          super(name).extend(SchemaElements::TypeReferenceExtension)
        end

        # Creates a new Results instance with JSON Schema extensions.
        #
        # @return [ElasticGraph::SchemaDefinition::Results] the created results instance
        def new_results
          super.extend(ResultsExtension)
        end

        # Creates a new SchemaArtifactManager instance with JSON Schema extensions.
        #
        # @return [ElasticGraph::SchemaDefinition::SchemaArtifactManager] the created artifact manager
        def new_schema_artifact_manager(...)
          super.extend(SchemaArtifactManagerExtension)
        end
      end
    end
  end
end
