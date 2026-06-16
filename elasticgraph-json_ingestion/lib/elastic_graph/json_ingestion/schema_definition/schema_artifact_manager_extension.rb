# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/constants"
require "elastic_graph/json_ingestion/schema_definition/json_schema_merge_reporter"
require "elastic_graph/json_ingestion/schema_definition/json_schema_pruner"
require "yaml"

module ElasticGraph
  module JSONIngestion
    module SchemaDefinition
      # Extension module for {ElasticGraph::SchemaDefinition::SchemaArtifactManager} that adds
      # JSON Schema artifact generation support.
      #
      # @private
      module SchemaArtifactManagerExtension
        # Overrides `dump_artifacts` to add JSON schema version bump checking before dumping.
        def dump_artifacts
          schema_results = json_ingestion_schema_definition_results
          state = json_ingestion_state

          json_ingestion_check_if_needs_json_schema_version_bump do |recommended_json_schema_version|
            if state.enforce_json_schema_version
              # @type var setter_location: ::Thread::Backtrace::Location
              # We use `_ =` because while `json_schema_version_setter_location` can be nil,
              # it'll never be nil if we get here and we want the type to be non-nilable.
              setter_location = _ = schema_results.json_schema_version_setter_location
              setter_location_path = ::Pathname.new(setter_location.absolute_path.to_s).relative_path_from(::Dir.pwd)

              abort "A change has been attempted to `json_schemas.yaml`, but the `json_schema_version` has not been correspondingly incremented. Please " \
                "increase the schema's version, and then run the `bundle exec rake schema_artifacts:dump` command again.\n\n" \
                "To update the schema version to the expected version, change line #{setter_location.lineno} at `#{setter_location_path}` to:\n" \
                "  `schema.json_schema_version #{recommended_json_schema_version}`\n\n" \
                "Alternately, call `schema.enforce_json_schema_version false` in your schema definition to allow the JSON schemas file " \
                "to change without requiring a version bump, but that is only recommended for non-production applications during initial schema prototyping."
            else
              @output.puts <<~EOS
                WARNING: the `json_schemas.yaml` artifact is being updated without the `json_schema_version` being correspondingly incremented.
                This is not recommended for production applications, but is currently allowed because you have called `schema.enforce_json_schema_version false`.
              EOS
            end
          end

          super
        end

        private

        # Returns the wrapped {ElasticGraph::SchemaDefinition::Results} narrowed to include this
        # gem's `ResultsExtension`. Centralizes the Steep cast that's needed because Steep can't
        # see the `extend(ResultsExtension)` applied at runtime.
        def json_ingestion_schema_definition_results
          schema_definition_results # : ElasticGraph::SchemaDefinition::Results & ResultsExtension
        end

        def json_ingestion_state
          json_ingestion_schema_definition_results.state # : ElasticGraph::SchemaDefinition::State & StateExtension
        end

        # Overrides the base `artifacts_from_schema_def` method to add JSON schema artifacts.
        def artifacts_from_schema_def
          json_schemas_artifact = json_ingestion_json_schemas_artifact
          versioned_artifacts = json_ingestion_build_desired_versioned_json_schemas(json_schemas_artifact.desired_contents).values.map do |versioned_schema|
            json_ingestion_new_versioned_json_schema_artifact(versioned_schema)
          end

          super + [json_schemas_artifact] + versioned_artifacts
        end

        def json_ingestion_json_schemas_artifact
          @json_ingestion_json_schemas_artifact ||= new_yaml_artifact(
            JSON_SCHEMAS_FILE,
            JSONSchemaPruner.prune(json_ingestion_schema_definition_results.current_public_json_schema),
            extra_comment_lines: [
              "This is the \"public\" JSON schema file and is intended to be provided to publishers so that",
              "they can perform code generation and event validation."
            ]
          )
        end

        def json_ingestion_check_if_needs_json_schema_version_bump(&block)
          if json_ingestion_json_schemas_artifact.out_of_date?
            existing_schema_version = json_ingestion_json_schemas_artifact.existing_dumped_contents&.dig(JSON_SCHEMA_VERSION_KEY) || -1
            desired_schema_version = json_ingestion_json_schemas_artifact.desired_contents[JSON_SCHEMA_VERSION_KEY]

            if existing_schema_version >= desired_schema_version
              yield existing_schema_version + 1
            end
          end
        end

        def json_ingestion_build_desired_versioned_json_schemas(current_public_json_schema)
          schema_results = json_ingestion_schema_definition_results
          versioned_parsed_yamls = ::Dir.glob(::File.join(@schema_artifacts_directory, JSON_SCHEMAS_BY_VERSION_DIRECTORY, "v*.yaml")).map do |file|
            ::YAML.safe_load_file(file)
          end + [current_public_json_schema]

          results_by_json_schema_version = versioned_parsed_yamls.to_h do |parsed_yaml|
            merged_schema = schema_results.merge_field_metadata_into_json_schema(parsed_yaml)
            [merged_schema.json_schema_version, merged_schema]
          end

          json_ingestion_json_schema_merge_reporter.report_errors(results_by_json_schema_version.values)
          json_ingestion_json_schema_merge_reporter.report_warnings(schema_results.unused_deprecated_elements)

          results_by_json_schema_version.transform_values(&:json_schema)
        end

        def json_ingestion_json_schema_merge_reporter
          @json_ingestion_json_schema_merge_reporter ||= JSONSchemaMergeReporter.new(@output)
        end

        def json_ingestion_new_versioned_json_schema_artifact(desired_contents)
          # File name depends on the schema_version field in the json schema.
          schema_version = desired_contents[JSON_SCHEMA_VERSION_KEY]

          new_yaml_artifact(
            ::File.join(JSON_SCHEMAS_BY_VERSION_DIRECTORY, "v#{schema_version}.yaml"),
            desired_contents,
            extra_comment_lines: [
              "This JSON schema file contains internal ElasticGraph metadata and should be considered private.",
              "The unversioned JSON schema file is public and intended to be provided to publishers."
            ]
          )
        end
      end
    end
  end
end
