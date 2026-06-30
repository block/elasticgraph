# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/constants"
require "elastic_graph/json_ingestion/schema_definition/indexing/field_type/enum"
require "elastic_graph/json_ingestion/schema_definition/indexing/field_type/object"
require "elastic_graph/json_ingestion/schema_definition/indexing/field_type/scalar"
require "elastic_graph/json_ingestion/schema_definition/indexing/field_type/union"
require "elastic_graph/json_ingestion/schema_definition/indexing/index_extension"
require "elastic_graph/graphql/scalar_coercion_adapters/valid_time_zones"
require "elastic_graph/json_ingestion/schema_definition/results_extension"
require "elastic_graph/json_ingestion/schema_definition/schema_artifact_manager_extension"
require "elastic_graph/json_ingestion/schema_definition/schema_elements/enum_type_extension"
require "elastic_graph/json_ingestion/schema_definition/schema_elements/field_extension"
require "elastic_graph/json_ingestion/schema_definition/schema_elements/scalar_type_extension"
require "elastic_graph/json_ingestion/schema_definition/schema_elements/type_with_subfields_extension"

module ElasticGraph
  module JSONIngestion
    module SchemaDefinition
      # Extension module applied to `ElasticGraph::SchemaDefinition::Factory` to wire up
      # JSON Schema support on Results and SchemaArtifactManager instances.
      #
      # @api private
      module FactoryExtension
        # Default JSON schema options applied to ElasticGraph's built-in scalar types as they
        # are constructed. Keyed by the un-overridden type name, because built-in type
        # registration always uses the canonical type name before `type_name_overrides` are
        # applied to the resulting type reference.
        BUILT_IN_SCALAR_JSON_SCHEMA_OPTIONS_BY_NAME = {
          "Boolean" => {type: "boolean"},
          "Float" => {type: "number"},
          "ID" => {type: "string"},
          "Int" => {type: "integer", minimum: INT_MIN, maximum: INT_MAX},
          "String" => {type: "string"},
          "Cursor" => {type: "string"},
          "Date" => {type: "string", format: "date"},
          "DateTime" => {type: "string", format: "date-time"},
          "LocalTime" => {type: "string", pattern: VALID_LOCAL_TIME_JSON_SCHEMA_PATTERN},
          "TimeZone" => {type: "string", enum: GraphQL::ScalarCoercionAdapters::VALID_TIME_ZONES.to_a.freeze},
          "Untyped" => {type: ["array", "boolean", "integer", "number", "object", "string"].freeze},
          "JsonSafeLong" => {type: "integer", minimum: JSON_SAFE_LONG_MIN, maximum: JSON_SAFE_LONG_MAX},
          "LongString" => {type: "integer", minimum: LONG_STRING_MIN, maximum: LONG_STRING_MAX}
        }.freeze

        # @private
        def new_enum_type(name)
          super(name) do |type|
            extended_type = type.extend(SchemaElements::EnumTypeExtension) # : ::ElasticGraph::SchemaDefinition::SchemaElements::EnumType & SchemaElements::EnumTypeExtension
            yield extended_type if block_given?
          end
        end

        # @private
        def new_enum_indexing_field_type(enum_value_names)
          Indexing::FieldType::Enum.new(super)
        end

        # @private
        def new_field(**kwargs)
          super(**kwargs) do |field|
            extended_field = field.extend(SchemaElements::FieldExtension) # : ::ElasticGraph::SchemaDefinition::SchemaElements::Field & SchemaElements::FieldExtension
            yield extended_field if block_given?
          end
        end

        # @private
        def new_index(name, settings, type)
          super(name, settings, type) do |index|
            extended_index = index.extend(Indexing::IndexExtension) # : ::ElasticGraph::SchemaDefinition::Indexing::Index & Indexing::IndexExtension
            yield extended_index if block_given?
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
            if state.initially_registered_built_in_types.empty? && (options = BUILT_IN_SCALAR_JSON_SCHEMA_OPTIONS_BY_NAME[name.to_s])
              extended_type.json_schema(**options)
            end

            yield extended_type if block_given?
            extended_type.finalize_json_schema_configuration!
          end
        end

        # @private
        def new_scalar_indexing_field_type(scalar_type:)
          Indexing::FieldType::Scalar.new(super)
        end

        # @private
        def new_type_with_subfields(schema_kind, name, wrapping_type:, field_factory:)
          super(schema_kind, name, wrapping_type: wrapping_type, field_factory: field_factory) do |type|
            extended_type = type.extend(SchemaElements::TypeWithSubfieldsExtension) # : ::ElasticGraph::SchemaDefinition::SchemaElements::TypeWithSubfields & SchemaElements::TypeWithSubfieldsExtension
            yield extended_type if block_given?
          end
        end

        # @private
        def new_union_indexing_field_type(subtypes_by_name)
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
