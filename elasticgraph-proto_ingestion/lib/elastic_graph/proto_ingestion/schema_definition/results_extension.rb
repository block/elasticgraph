# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/proto_ingestion/indexer_extension"
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

        # Adds private protobuf field metadata to the registered runtime extension.
        # @return [SchemaArtifacts::RuntimeMetadata::Schema]
        def runtime_metadata
          metadata = super
          extension = SchemaArtifacts::RuntimeMetadata::ComponentExtension.new({
            "name" => "ElasticGraph::ProtoIngestion::IndexerExtension",
            "require_path" => "elastic_graph/proto_ingestion/indexer_extension",
            "config" => protobuf_schema_generator.ingestion_metadata
          })
          metadata.with(indexer_extension_modules: metadata.indexer_extension_modules + [extension])
        end

        private

        def protobuf_schema_generator
          @protobuf_schema_generator ||= begin
            # The cast is needed because Steep can't see the `extend(StateExtension)` applied at
            # runtime in {APIExtension.extended}.
            extension_state = state # : ElasticGraph::SchemaDefinition::State & StateExtension

            Schema.new(
              state: extension_state,
              all_types: all_types,
              ingestion_state: extension_state.proto_ingestion_state,
              sourced_type_names: sourced_update_targets_by_source_type_name.keys
            )
          end
        end
      end
    end
  end
end
