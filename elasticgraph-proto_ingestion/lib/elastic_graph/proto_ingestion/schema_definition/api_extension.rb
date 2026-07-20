# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/proto_ingestion"
require "elastic_graph/proto_ingestion/schema_definition/factory_extension"
require "elastic_graph/proto_ingestion/schema_definition/identifier"
require "elastic_graph/proto_ingestion/schema_definition/schema"
require "elastic_graph/proto_ingestion/schema_definition/state_extension"

module ElasticGraph
  module ProtoIngestion
    # Namespace for all protobuf schema definition support.
    #
    # {SchemaDefinition::APIExtension} is the primary entry point and should be used as a schema definition extension module.
    module SchemaDefinition
      # Module designed to be extended onto an {ElasticGraph::SchemaDefinition::API} instance
      # to enable protobuf schema artifact generation.
      module APIExtension
        # Wires up the protobuf extensions when this module is extended onto an API instance.
        #
        # @param api [ElasticGraph::SchemaDefinition::API] the API instance to extend
        # @return [void]
        # @api private
        def self.extended(api)
          api.state.extend(StateExtension)
          api.factory.extend(FactoryExtension)
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
        def proto_schema_artifacts(package_name:)
          proto_ingestion_state.package_name = Identifier.validate_package_name(package_name)
          nil
        end

        private

        # Returns this gem's state container. Centralizes the Steep cast that's needed because
        # Steep can't see the `extend(StateExtension)` applied at runtime in `extended`.
        def proto_ingestion_state
          extension_state = state # : ElasticGraph::SchemaDefinition::State & StateExtension
          extension_state.proto_ingestion_state
        end
      end
    end
  end
end
