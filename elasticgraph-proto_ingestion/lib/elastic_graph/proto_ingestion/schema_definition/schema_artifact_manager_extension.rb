# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/proto_ingestion"

module ElasticGraph
  module ProtoIngestion
    module SchemaDefinition
      # Extension module for {ElasticGraph::SchemaDefinition::SchemaArtifactManager} that adds
      # proto artifact generation support.
      #
      # @private
      module SchemaArtifactManagerExtension
        private

        # Overrides the base `artifacts_from_schema_def` method to add proto artifacts.
        def artifacts_from_schema_def
          base_artifacts = super
          proto_schema = protobuf_schema_definition_results.proto_schema
          return base_artifacts if proto_schema.empty?

          base_artifacts + [
            new_raw_artifact(PROTO_SCHEMA_FILE, proto_schema.chomp, comment_prefix: "//")
          ]
        end

        # Returns the wrapped {ElasticGraph::SchemaDefinition::Results} narrowed to include this
        # gem's `ResultsExtension`. Centralizes the Steep cast that's needed because Steep can't
        # see the `extend(ResultsExtension)` applied at runtime.
        def protobuf_schema_definition_results
          schema_definition_results # : ElasticGraph::SchemaDefinition::Results & ResultsExtension
        end
      end
    end
  end
end
