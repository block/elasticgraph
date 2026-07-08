# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/proto_ingestion"
require "yaml"

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
          protobuf_load_existing_field_number_mappings

          base_artifacts = super
          proto_schema = protobuf_schema_definition_results.proto_schema
          return base_artifacts if proto_schema.empty?

          base_artifacts + [
            new_yaml_artifact(
              PROTO_FIELD_NUMBERS_FILE,
              protobuf_schema_definition_results.proto_field_number_mappings,
              extra_comment_lines: [
                "This file reserves protobuf field and enum value numbers to keep them stable over time.",
                "Do not renumber existing entries."
              ]
            ),
            new_raw_artifact(PROTO_SCHEMA_FILE, proto_schema.chomp, comment_prefix: "//")
          ]
        end

        # Returns the wrapped {ElasticGraph::SchemaDefinition::Results} narrowed to include this
        # gem's `ResultsExtension`. Centralizes the Steep cast that's needed because Steep can't
        # see the `extend(ResultsExtension)` applied at runtime.
        def protobuf_schema_definition_results
          schema_definition_results # : ElasticGraph::SchemaDefinition::Results & ResultsExtension
        end

        def proto_ingestion_state
          extension_state = protobuf_schema_definition_results.state # : ElasticGraph::SchemaDefinition::State & StateExtension
          extension_state.proto_ingestion_state
        end

        # Seeds the schema generator with the field-number mappings from the previously dumped
        # artifact (if any) so that field numbers remain stable across dumps.
        def protobuf_load_existing_field_number_mappings
          full_path = ::File.join(@schema_artifacts_directory, PROTO_FIELD_NUMBERS_FILE)
          return unless ::File.exist?(full_path)

          proto_ingestion_state.field_number_mappings = ::YAML.safe_load_file(full_path, aliases: false)
        end
      end
    end
  end
end
