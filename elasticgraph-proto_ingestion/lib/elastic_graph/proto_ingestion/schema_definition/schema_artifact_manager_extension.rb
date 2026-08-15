# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/errors"
require "elastic_graph/proto_ingestion"

module ElasticGraph
  module ProtoIngestion
    module SchemaDefinition
      # Extension module for {ElasticGraph::SchemaDefinition::SchemaArtifactManager} that adds
      # proto artifact generation support.
      #
      # @private
      module SchemaArtifactManagerExtension
        PROTO_FIELD_NUMBERS_COMMENT_PREAMBLE_LINES = [
          "This file is part of your schema definition--not a regenerable schema artifact. It is an",
          "input to `schema.proto` generation: ElasticGraph reads it to keep protobuf field and enum",
          "value numbers stable as your schema evolves, and `rake schema_artifacts:dump` maintains it",
          "for you.",
          "",
          "You may update it by hand (e.g. to assign a specific number). While prototyping, you may",
          "delete this file and regenerate it to reset the number assignments.",
          "",
          "Once generated protos have been used to serialize data or consumed by another codebase,",
          "you must NOT delete this file and regenerate it. The original number assignments would be",
          "lost, and previously serialized protobuf messages would be misread."
        ].freeze

        private

        # Overrides the base `artifacts_from_schema_def` method to add proto artifacts.
        def artifacts_from_schema_def
          base_artifacts = super
          proto_schema = protobuf_schema_definition_results.proto_schema
          return base_artifacts if proto_schema.empty?

          base_artifacts + [
            proto_field_numbers_artifact,
            new_raw_artifact(PROTO_SCHEMA_FILE, proto_schema.chomp, comment_prefix: "//")
          ]
        end

        # Builds the `proto_field_numbers.yaml` artifact. The file is part of the schema definition
        # rather than a proper schema artifact--it's an input to `schema.proto` generation--so it
        # lives alongside `path_to_schema` instead of in the schema artifacts directory.
        def proto_field_numbers_artifact
          new_yaml_artifact(PROTO_FIELD_NUMBERS_FILE, protobuf_schema_definition_results.proto_field_number_mappings)
            .with(
              file_name: proto_field_numbers_path,
              comment_preamble_lines: PROTO_FIELD_NUMBERS_COMMENT_PREAMBLE_LINES
            )
        end

        def proto_field_numbers_path
          proto_ingestion_schema_definition_state.proto_field_numbers_path ||
            raise(Errors::SchemaError, "Cannot dump `#{PROTO_FIELD_NUMBERS_FILE}` without a configured `path_to_schema`.")
        end

        # Returns the wrapped {ElasticGraph::SchemaDefinition::Results} narrowed to include this
        # gem's `ResultsExtension`. Centralizes the Steep cast that's needed because Steep can't
        # see the `extend(ResultsExtension)` applied at runtime.
        def protobuf_schema_definition_results
          schema_definition_results # : ElasticGraph::SchemaDefinition::Results & ResultsExtension
        end

        def proto_ingestion_schema_definition_state
          protobuf_schema_definition_results.state # : ElasticGraph::SchemaDefinition::State & StateExtension
        end
      end
    end
  end
end
