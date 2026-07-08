# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/proto_ingestion/schema_definition/schema"

module ElasticGraph
  module ProtoIngestion
    module SchemaDefinition
      # Extension module for {ElasticGraph::SchemaDefinition::Results} that adds proto schema generation support.
      module ResultsExtension
        # Returns the generated proto schema.
        #
        # @return [String] complete `proto3` schema file contents
        def proto_schema
          @proto_schema ||= protobuf_schema_generator.to_proto
        end

        # Returns proto field-number mappings suitable for artifact storage.
        #
        # @return [Hash]
        def proto_field_number_mappings
          # Ensure generation has occurred before reading mappings from the generator.
          proto_schema
          protobuf_schema_generator.field_number_mappings_for_artifact
        end

        private

        def protobuf_schema_generator
          @protobuf_schema_generator ||= begin
            # The cast is needed because Steep can't see the `extend(StateExtension)` applied at
            # runtime in {APIExtension.extended}.
            extension_state = state # : ElasticGraph::SchemaDefinition::State & StateExtension
            ingestion_state = extension_state.proto_ingestion_state

            Schema.new(
              state: extension_state,
              all_types: all_types,
              package_name: ingestion_state.package_name,
              proto_field_number_mappings: ingestion_state.field_number_mappings,
              syntax: ingestion_state.syntax,
              headers: ingestion_state.headers
            )
          end
        end
      end
    end
  end
end
