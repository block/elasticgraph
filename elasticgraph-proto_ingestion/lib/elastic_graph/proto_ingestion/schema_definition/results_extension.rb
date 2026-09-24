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
        # @return [Hash<String, Object>]
        def proto_field_number_mappings
          # Numbers get assigned as `schema.proto` renders, so we must render before reading them.
          proto_schema
          proto_envelope_schema
          protobuf_schema_generator.field_number_mappings_for_artifact
        end

        # Generated protobuf envelope and batch definitions.
        # @return [String]
        def proto_envelope_schema
          protobuf_schema_generator.envelope_schema
        end

        private

        def protobuf_schema_generator
          @protobuf_schema_generator ||= begin
            # The cast is needed because Steep can't see the `extend(StateExtension)` applied at
            # runtime in {APIExtension.extended}.
            extension_state = state # : ElasticGraph::SchemaDefinition::State & StateExtension

            # Resolve `sourced_from` update targets (via `ingestible_types_by_name`) before touching `all_types` so that `sourced_from`
            # validation errors take precedence over any errors raised while generating derived types.
            ingestible_types = ingestible_types_by_name

            Schema.new(
              state: extension_state,
              all_types: all_types,
              ingestion_state: extension_state.proto_ingestion_state,
              ingestible_types_by_name: ingestible_types
            )
          end
        end
      end
    end
  end
end
