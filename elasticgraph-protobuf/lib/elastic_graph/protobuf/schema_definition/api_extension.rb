# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/errors"
require "elastic_graph/protobuf"
require "elastic_graph/protobuf/schema_definition/factory_extension"
require "elastic_graph/protobuf/schema_definition/state_extension"

module ElasticGraph
  module Protobuf
    # Namespace for all protobuf schema definition support.
    #
    # {SchemaDefinition::APIExtension} is the primary entry point and should be used as a schema definition extension module.
    module SchemaDefinition
      # Module designed to be extended onto an {ElasticGraph::SchemaDefinition::API} instance
      # to enable protobuf schema artifact generation.
      module APIExtension
        # Maps built-in ElasticGraph scalar types to proto field types.
        PROTO_TYPES_BY_BUILT_IN_SCALAR_TYPE = {
          "Boolean" => "bool",
          "Cursor" => "string",
          "Date" => "string",
          "DateTime" => "string",
          "Float" => "double",
          "ID" => "string",
          "Int" => "int32",
          "JsonSafeLong" => "int64",
          "LocalTime" => "string",
          "LongString" => "int64",
          "String" => "string",
          "TimeZone" => "string",
          "Untyped" => "string"
        }.freeze

        # Wires up the protobuf extensions when this module is extended onto an API instance.
        #
        # @param api [ElasticGraph::SchemaDefinition::API] the API instance to extend
        # @return [void]
        # @api private
        def self.extended(api)
          api.state.extend(StateExtension)
          api.factory.extend(FactoryExtension)

          api.on_built_in_types do |type|
            if type.is_a?(ScalarTypeExtension)
              type.proto_field type: PROTO_TYPES_BY_BUILT_IN_SCALAR_TYPE.fetch(type.name)
            end
          end
        end

        # Configures protobuf artifact generation behavior.
        #
        # @param package_name [String] proto package name to emit
        # @return [void]
        #
        # @example Set the proto package name
        #   ElasticGraph.define_schema do |schema|
        #     schema.proto_schema_artifacts package_name: "myapp.events.v1"
        #   end
        def proto_schema_artifacts(package_name: "elasticgraph")
          if !package_name.is_a?(String) || package_name.empty?
            raise Errors::SchemaError, "`package_name` must be a non-empty String"
          end

          protobuf_state.proto_schema_package_name = package_name
          nil
        end

        # Registers mappings from GraphQL enum names to protobuf enum classes and transform options.
        # This is intended to support reusing enum mappings already maintained by applications
        # (for example in schema/proto consistency tests).
        #
        # @param proto_enums_by_graphql_enum [Hash]
        # @return [void]
        def proto_enum_mappings(proto_enums_by_graphql_enum)
          protobuf_state.proto_enums_by_graphql_enum = proto_enums_by_graphql_enum
          nil
        end

        # Configures proto field-number mappings directly from a hash.
        # Useful for tests and advanced use cases where mappings are sourced outside artifacts.
        # When artifacts are dumped, mappings from the existing `proto_field_numbers.yaml` artifact
        # are loaded automatically; this method does not need to be called in that case.
        #
        # @param proto_field_number_mappings [Hash]
        # @return [void]
        def configure_proto_field_number_mappings(proto_field_number_mappings)
          protobuf_state.proto_field_number_mappings = proto_field_number_mappings
          nil
        end

        private

        # Returns the API's `state` narrowed to include this gem's `StateExtension`. Centralizes
        # the Steep cast that's needed because Steep can't see the `extend(StateExtension)` applied
        # at runtime in `extended`.
        def protobuf_state
          state # : ElasticGraph::SchemaDefinition::State & StateExtension
        end
      end
    end
  end
end
