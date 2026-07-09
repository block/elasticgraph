# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/proto_ingestion/schema_definition/results_extension"
require "elastic_graph/proto_ingestion/schema_definition/schema_artifact_manager_extension"
require "elastic_graph/proto_ingestion/schema_definition/schema_elements/enum_type_extension"
require "elastic_graph/proto_ingestion/schema_definition/schema_elements/enum_value_extension"
require "elastic_graph/proto_ingestion/schema_definition/schema_elements/object_interface_and_union_extension"
require "elastic_graph/proto_ingestion/schema_definition/schema_elements/scalar_type_extension"

module ElasticGraph
  module ProtoIngestion
    module SchemaDefinition
      # Extension module applied to Factory to add proto support.
      module FactoryExtension
        # Default protobuf options applied to ElasticGraph's built-in scalar types as they are constructed.
        BUILT_IN_SCALAR_PROTO_OPTIONS_BY_NAME = {
          "Boolean" => {type: "bool"},
          "Cursor" => {type: "string"},
          "Date" => {type: "string", comment: %(ISO 8601 date, e.g. "2024-11-25")},
          "DateTime" => {type: "google.protobuf.Timestamp", import: "google/protobuf/timestamp.proto"},
          "Float" => {type: "double"},
          "ID" => {type: "string"},
          "Int" => {type: "int32"},
          "JsonSafeLong" => {type: "int64"},
          "LocalTime" => {type: "string", comment: %(ISO 8601 local time, e.g. "14:23:12")},
          "LongString" => {type: "int64"},
          "String" => {type: "string"},
          "TimeZone" => {type: "string", comment: %(IANA time zone identifier, e.g. "America/Los_Angeles")},
          "Untyped" => {type: "string"}
        }.freeze

        # Creates a new enum type with proto extensions.
        #
        # @param name [String] enum type name
        # @yield [ElasticGraph::SchemaDefinition::SchemaElements::EnumType]
        # @return [ElasticGraph::SchemaDefinition::SchemaElements::EnumType]
        def new_enum_type(name)
          super(name) do |type|
            extended_type = type.extend(SchemaElements::EnumTypeExtension) # : ::ElasticGraph::SchemaDefinition::SchemaElements::EnumType & SchemaElements::EnumTypeExtension
            yield extended_type if block_given?
            register_proto_type_name(extended_type)
          end
        end

        # Creates a new enum value with proto extensions.
        #
        # @param name [String] enum value name
        # @param original_name [String] enum value name before overrides
        # @yield [ElasticGraph::SchemaDefinition::SchemaElements::EnumValue]
        # @return [ElasticGraph::SchemaDefinition::SchemaElements::EnumValue]
        def new_enum_value(name, original_name)
          super(name, original_name) do |value|
            extended_value = value.extend(SchemaElements::EnumValueExtension) # : ::ElasticGraph::SchemaDefinition::SchemaElements::EnumValue & SchemaElements::EnumValueExtension
            yield extended_value if block_given?
          end
        end

        # Creates a new interface type with proto extensions.
        #
        # @param name [String] interface type name
        # @yield [ElasticGraph::SchemaDefinition::SchemaElements::InterfaceType]
        # @return [ElasticGraph::SchemaDefinition::SchemaElements::InterfaceType]
        def new_interface_type(name)
          super(name) do |type|
            extended_type = type.extend(SchemaElements::ObjectInterfaceAndUnionExtension) # : ::ElasticGraph::SchemaDefinition::SchemaElements::InterfaceType & SchemaElements::ObjectInterfaceAndUnionExtension
            yield extended_type if block_given?
            register_proto_type_name(extended_type)
          end
        end

        # Creates a new object type with proto extensions.
        #
        # @param name [String] object type name
        # @yield [ElasticGraph::SchemaDefinition::SchemaElements::ObjectType]
        # @return [ElasticGraph::SchemaDefinition::SchemaElements::ObjectType]
        def new_object_type(name)
          super(name) do |type|
            extended_type = type.extend(SchemaElements::ObjectInterfaceAndUnionExtension) # : ::ElasticGraph::SchemaDefinition::SchemaElements::ObjectType & SchemaElements::ObjectInterfaceAndUnionExtension
            yield extended_type if block_given?
            register_proto_type_name(extended_type)
          end
        end

        # Creates a new scalar type with proto extensions.
        #
        # @param name [String] scalar type name
        # @yield [ElasticGraph::SchemaDefinition::SchemaElements::ScalarType]
        # @return [ElasticGraph::SchemaDefinition::SchemaElements::ScalarType]
        def new_scalar_type(name)
          super(name) do |type|
            extended_type = type.extend(SchemaElements::ScalarTypeExtension) # : ::ElasticGraph::SchemaDefinition::SchemaElements::ScalarType & SchemaElements::ScalarTypeExtension

            if state.initially_registered_built_in_types.empty? &&
                (proto_options = BUILT_IN_SCALAR_PROTO_OPTIONS_BY_NAME[name.to_s])
              extended_type.protobuf(
                type: proto_options.fetch(:type),
                import: proto_options[:import],
                comment: proto_options[:comment]
              )
            end

            yield extended_type if block_given?
            extended_type.finalize_protobuf_configuration!
          end
        end

        # Creates a new union type with proto extensions.
        #
        # @param name [String] union type name
        # @yield [ElasticGraph::SchemaDefinition::SchemaElements::UnionType]
        # @return [ElasticGraph::SchemaDefinition::SchemaElements::UnionType]
        def new_union_type(name)
          super(name) do |type|
            extended_type = type.extend(SchemaElements::ObjectInterfaceAndUnionExtension) # : ::ElasticGraph::SchemaDefinition::SchemaElements::UnionType & SchemaElements::ObjectInterfaceAndUnionExtension
            yield extended_type if block_given?
            register_proto_type_name(extended_type)
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

        private

        def register_proto_type_name(type)
          extension_state = state # : ElasticGraph::SchemaDefinition::State & StateExtension
          extension_state.proto_ingestion_state.register_proto_type_name(type.proto_name, type.name)
        end
      end
    end
  end
end
