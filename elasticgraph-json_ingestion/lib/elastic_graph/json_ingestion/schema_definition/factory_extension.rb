# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/json_ingestion/schema_definition/indexing/field_type/enum"
require "elastic_graph/json_ingestion/schema_definition/indexing/field_type/object"
require "elastic_graph/json_ingestion/schema_definition/indexing/field_type/scalar"
require "elastic_graph/json_ingestion/schema_definition/indexing/field_type/union"
require "elastic_graph/json_ingestion/schema_definition/indexing/index_extension"
require "elastic_graph/json_ingestion/schema_definition/results_extension"
require "elastic_graph/json_ingestion/schema_definition/schema_artifact_manager_extension"
require "elastic_graph/json_ingestion/schema_definition/schema_elements/enum_type_extension"
require "elastic_graph/json_ingestion/schema_definition/schema_elements/field_extension"
require "elastic_graph/json_ingestion/schema_definition/schema_elements/scalar_type_extension"
require "elastic_graph/json_ingestion/schema_definition/schema_elements/type_with_subfields_extension"
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
            extended_type = type.extend(SchemaElements::EnumTypeExtension) # : ::ElasticGraph::SchemaDefinition::SchemaElements::EnumType & SchemaElements::EnumTypeExtension
            yield extended_type if block_given?
          end
        end

        # @private
        def new_enum_indexing_field_type(...)
          Indexing::FieldType::Enum.new(super)
        end

        # @private
        def new_field(**kwargs, &block)
          super(**kwargs) do |field|
            extended_field = field.extend(SchemaElements::FieldExtension) # : ::ElasticGraph::SchemaDefinition::SchemaElements::Field & SchemaElements::FieldExtension
            block&.call(extended_field)
          end
        end

        # @private
        def new_index(name, settings, type, &block)
          super(name, settings, type) do |index|
            extended_index = index.extend(Indexing::IndexExtension) # : ::ElasticGraph::SchemaDefinition::Indexing::Index & Indexing::IndexExtension
            block&.call(extended_index)
          end
        end

        # @private
        def new_object_indexing_field_type(...)
          Indexing::FieldType::Object.new(super)
        end

        # @private
        def new_scalar_type(name)
          super(name) do |type|
            extended_type = type.extend(SchemaElements::ScalarTypeExtension) # : ::ElasticGraph::SchemaDefinition::SchemaElements::ScalarType & SchemaElements::ScalarTypeExtension
            yield extended_type if block_given?
            extended_type.validate_json_schema_configuration! unless state.initially_registered_built_in_types.empty?
          end
        end

        # @private
        def new_scalar_indexing_field_type(...)
          Indexing::FieldType::Scalar.new(super)
        end

        # @private
        def new_type_reference(name)
          super(name).extend(SchemaElements::TypeReferenceExtension)
        end

        # @private
        def new_type_with_subfields(schema_kind, name, wrapping_type:, field_factory:)
          super(schema_kind, name, wrapping_type: wrapping_type, field_factory: field_factory) do |type|
            extended_type = type.extend(SchemaElements::TypeWithSubfieldsExtension) # : ::ElasticGraph::SchemaDefinition::SchemaElements::TypeWithSubfields & SchemaElements::TypeWithSubfieldsExtension
            yield extended_type
          end
        end

        # @private
        def new_union_indexing_field_type(...)
          Indexing::FieldType::Union.new(super)
        end

        # Creates a new Results instance with JSON Schema extensions.
        #
        # @return [ElasticGraph::SchemaDefinition::Results] the created results instance
        def new_results
          super.tap do |results|
            results.extend(ResultsExtension)
          end
        end

        # Creates a new SchemaArtifactManager instance with JSON Schema extensions.
        #
        # @return [ElasticGraph::SchemaDefinition::SchemaArtifactManager] the created artifact manager
        def new_schema_artifact_manager(...)
          super.tap do |manager|
            manager.extend(SchemaArtifactManagerExtension)
          end
        end
      end
    end
  end
end
