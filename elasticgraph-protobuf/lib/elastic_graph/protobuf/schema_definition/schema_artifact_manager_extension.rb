# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/protobuf"
require "yaml"

module ElasticGraph
  module Protobuf
    module SchemaDefinition
      # Extension module for SchemaArtifactManager that adds proto artifact generation support.
      module SchemaArtifactManagerExtension
        private

        def artifacts_from_schema_def
          results = schema_definition_results # : ElasticGraph::SchemaDefinition::Results & ResultsExtension
          load_proto_field_number_mappings(results)

          base_artifacts = super
          proto_schema = results.respond_to?(:proto_schema) ? results.proto_schema : ""
          return base_artifacts if proto_schema.empty?

          base_artifacts + [
            new_yaml_artifact(
              PROTO_FIELD_NUMBERS_FILE,
              results.proto_field_number_mappings,
              extra_comment_lines: [
                "This file reserves protobuf field numbers to keep them stable over time.",
                "Do not renumber existing entries."
              ]
            ),
            new_raw_artifact(PROTO_SCHEMA_FILE, proto_schema.chomp)
          ]
        end

        def load_proto_field_number_mappings(results)
          api = results.state.api
          return unless api.respond_to?(:configure_proto_field_number_mappings)

          full_path = ::File.join(@schema_artifacts_directory, PROTO_FIELD_NUMBERS_FILE)
          loaded = ::File.exist?(full_path) ? ::YAML.safe_load_file(full_path, aliases: false) : {}
          api.configure_proto_field_number_mappings(loaded || {})
        end
      end
    end
  end
end
