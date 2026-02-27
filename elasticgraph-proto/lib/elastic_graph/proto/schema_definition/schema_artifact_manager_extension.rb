# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/proto"
require "pathname"
require "yaml"

module ElasticGraph
  module Proto
    module SchemaDefinition
      # Extension module for SchemaArtifactManager that adds proto artifact generation support.
      module SchemaArtifactManagerExtension
        private

        def artifacts_from_schema_def
          results = schema_definition_results # : ElasticGraph::SchemaDefinition::Results & ResultsExtension
          load_proto_field_number_mappings(results)

          base_artifacts = super

          if replace_json_schema_artifacts_with_proto?(results)
            base_artifacts = base_artifacts.reject { |artifact| json_schema_artifact?(artifact.file_name) }
          end

          proto_schema = results.respond_to?(:proto_schema) ? results.proto_schema : ""
          field_number_mapping_file = proto_field_number_mapping_file(results)

          if results.respond_to?(:proto_field_number_mappings) && field_number_mapping_file
            base_artifacts += [
              new_yaml_artifact(
                field_number_mapping_file,
                results.proto_field_number_mappings,
                extra_comment_lines: [
                  "This file reserves protobuf field numbers to keep them stable over time.",
                  "Do not renumber existing entries."
                ]
              )
            ]
          end

          return base_artifacts if proto_schema.empty?

          base_artifacts + [new_raw_artifact(PROTO_SCHEMA_FILE, proto_schema.chomp)]
        end

        # Skip json-schema-version enforcement when proto fully replaces json schema artifacts.
        def check_if_needs_json_schema_version_bump(...)
          return if replace_json_schema_artifacts_with_proto?(schema_definition_results)

          super
        end

        # Skip versioned json-schema generation/merge checks when proto fully replaces json schema artifacts.
        def build_desired_versioned_json_schemas(...)
          return {} if replace_json_schema_artifacts_with_proto?(schema_definition_results)

          super
        end

        def replace_json_schema_artifacts_with_proto?(results)
          results.respond_to?(:replace_json_schema_artifacts_with_proto?) &&
            results.replace_json_schema_artifacts_with_proto?
        end

        def json_schema_artifact?(file_name)
          file_name.end_with?(JSON_SCHEMAS_FILE) ||
            file_name.include?("/#{JSON_SCHEMAS_BY_VERSION_DIRECTORY}/") ||
            file_name.include?("\\#{JSON_SCHEMAS_BY_VERSION_DIRECTORY}\\")
        end

        def proto_field_number_mapping_file(results)
          return nil unless results.state.api.respond_to?(:proto_field_number_mapping_file)

          results.state.api.proto_field_number_mapping_file
        end

        def load_proto_field_number_mappings(results)
          api = results.state.api
          return unless api.respond_to?(:configure_proto_field_number_mappings)

          mapping_file = proto_field_number_mapping_file(results)
          return if mapping_file.nil?

          full_path =
            if ::Pathname.new(mapping_file).absolute?
              mapping_file
            else
              ::File.join(@schema_artifacts_directory, mapping_file)
            end

          if ::File.exist?(full_path)
            loaded = ::YAML.safe_load_file(full_path, aliases: false)
            mappings = loaded.nil? ? {} : loaded
          else
            if api.respond_to?(:enforce_proto_field_number_mappings?) && api.enforce_proto_field_number_mappings?
              raise ::ElasticGraph::Errors::SchemaError, "Proto field-number mapping enforcement is enabled, but mapping file " \
                "`#{mapping_file}` does not exist in `#{@schema_artifacts_directory}`."
            end

            mappings = {}
          end

          enforce = api.respond_to?(:enforce_proto_field_number_mappings?) && api.enforce_proto_field_number_mappings?
          api.configure_proto_field_number_mappings(mappings, enforce: enforce)
        end
      end
    end
  end
end
