# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/constants"
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
          check_if_needs_json_schema_version_bump do |recommended_json_schema_version|
            if @enforce_json_schema_version
              # @type var setter_location: ::Thread::Backtrace::Location
              # We use `_ =` because while `json_schema_version_setter_location` can be nil,
              # it'll never be nil if we get here and we want the type to be non-nilable.
              setter_location = _ = schema_definition_results.json_schema_version_setter_location
              setter_location_path = ::Pathname.new(setter_location.absolute_path.to_s).relative_path_from(::Dir.pwd)

              abort "A change has been attempted to `json_schemas.yaml`, but the `json_schema_version` has not been correspondingly incremented. Please " \
                "increase the schema's version, and then run the `bundle exec rake schema_artifacts:dump` command again.\n\n" \
                "To update the schema version to the expected version, change line #{setter_location.lineno} at `#{setter_location_path}` to:\n" \
                "  `schema.json_schema_version #{recommended_json_schema_version}`\n\n" \
                "Alternately, pass `enforce_json_schema_version: false` to `ElasticGraph::SchemaDefinition::RakeTasks.new` to allow the JSON schemas " \
                "file to change without requiring a version bump, but that is only recommended for non-production applications during initial schema prototyping."
            else
              @output.puts <<~EOS
                WARNING: the `json_schemas.yaml` artifact is being updated without the `json_schema_version` being correspondingly incremented.
                This is not recommended for production applications, but is currently allowed because you have set `enforce_json_schema_version: false`.
              EOS
            end
          end

          super
        end

        private

        # Overrides the base `artifacts_from_schema_def` method to add JSON schema artifacts.
        def artifacts_from_schema_def
          base_artifacts = super

          versioned_artifacts = build_desired_versioned_json_schemas(json_schemas_artifact.desired_contents).values.map do |versioned_schema|
            new_versioned_json_schema_artifact(versioned_schema)
          end

          base_artifacts + [json_schemas_artifact] + versioned_artifacts
        end

        def json_schemas_artifact
          @json_schemas_artifact ||= new_yaml_artifact(
            JSON_SCHEMAS_FILE,
            JSONSchemaPruner.prune(schema_definition_results.current_public_json_schema),
            extra_comment_lines: [
              "This is the \"public\" JSON schema file and is intended to be provided to publishers so that",
              "they can perform code generation and event validation."
            ]
          )
        end

        def check_if_needs_json_schema_version_bump(&block)
          if json_schemas_artifact.out_of_date?
            existing_schema_version = json_schemas_artifact.existing_dumped_contents&.dig(JSON_SCHEMA_VERSION_KEY) || -1
            desired_schema_version = json_schemas_artifact.desired_contents[JSON_SCHEMA_VERSION_KEY]

            if existing_schema_version >= desired_schema_version
              yield existing_schema_version + 1
            end
          end
        end

        def build_desired_versioned_json_schemas(current_public_json_schema)
          versioned_parsed_yamls = ::Dir.glob(::File.join(@schema_artifacts_directory, JSON_SCHEMAS_BY_VERSION_DIRECTORY, "v*.yaml")).map do |file|
            ::YAML.safe_load_file(file)
          end + [current_public_json_schema]

          results_by_json_schema_version = versioned_parsed_yamls.to_h do |parsed_yaml|
            merged_schema = @schema_definition_results.merge_field_metadata_into_json_schema(parsed_yaml)
            [merged_schema.json_schema_version, merged_schema]
          end

          report_json_schema_merge_errors(results_by_json_schema_version.values)
          report_json_schema_merge_warnings

          results_by_json_schema_version.transform_values(&:json_schema)
        end

        def report_json_schema_merge_errors(merged_results)
          json_schema_versions_by_missing_field = ::Hash.new { |h, k| h[k] = [] } # : ::Hash[::String, ::Array[::Integer]]
          json_schema_versions_by_missing_type = ::Hash.new { |h, k| h[k] = [] } # : ::Hash[::String, ::Array[::Integer]]
          json_schema_versions_by_missing_necessary_field = ::Hash.new { |h, k| h[k] = [] } # : ::Hash[Indexing::JSONSchemaWithMetadata::MissingNecessaryField, ::Array[::Integer]]

          merged_results.each do |result|
            result.missing_fields.each do |field|
              json_schema_versions_by_missing_field[field] << result.json_schema_version
            end

            result.missing_types.each do |type|
              json_schema_versions_by_missing_type[type] << result.json_schema_version
            end

            result.missing_necessary_fields.each do |missing_necessary_field|
              json_schema_versions_by_missing_necessary_field[missing_necessary_field] << result.json_schema_version
            end
          end

          missing_field_errors = json_schema_versions_by_missing_field.map do |field, json_schema_versions|
            missing_field_error_for(field, json_schema_versions)
          end

          missing_type_errors = json_schema_versions_by_missing_type.map do |type, json_schema_versions|
            missing_type_error_for(type, json_schema_versions)
          end

          missing_necessary_field_errors = json_schema_versions_by_missing_necessary_field.map do |field, json_schema_versions|
            missing_necessary_field_error_for(field, json_schema_versions)
          end

          definition_conflict_errors = merged_results
            .flat_map { |result| result.definition_conflicts.to_a }
            .group_by(&:name)
            .map do |name, deprecated_elements|
              <<~EOS
                The schema definition of `#{name}` has conflicts. To resolve the conflict, remove the unneeded definitions from the following:

                #{format_deprecated_elements(deprecated_elements)}
              EOS
            end

          errors = missing_field_errors + missing_type_errors + missing_necessary_field_errors + definition_conflict_errors
          return if errors.empty?

          abort errors.join("\n\n")
        end

        def report_json_schema_merge_warnings
          unused_elements = @schema_definition_results.unused_deprecated_elements
          return if unused_elements.empty?

          @output.puts <<~EOS
            The schema definition has #{unused_elements.size} unneeded reference(s) to deprecated schema elements. These can all be safely deleted:

            #{format_deprecated_elements(unused_elements)}

          EOS
        end

        def format_deprecated_elements(deprecated_elements)
          descriptions = deprecated_elements
            .sort_by { |e| [e.defined_at.path, e.defined_at.lineno] }
            .map(&:description)
            .uniq

          descriptions.each.with_index(1).map { |desc, idx| "#{idx}. #{desc}" }.join("\n")
        end

        def missing_field_error_for(qualified_field, json_schema_versions)
          type, field = qualified_field.split(".")

          <<~EOS
            The `#{qualified_field}` field (which existed in #{describe_json_schema_versions(json_schema_versions, "and")}) no longer exists in the current schema definition.
            ElasticGraph cannot guess what it should do with this field's data when ingesting events at #{old_versions(json_schema_versions)}.
            To continue, do one of the following:

            1. If the `#{qualified_field}` field has been renamed, indicate this by calling `field.renamed_from "#{field}"` on the renamed field.
            2. If the `#{qualified_field}` field has been dropped, indicate this by calling `type.deleted_field "#{field}"` on the `#{type}` type.
            3. Alternately, if no publishers or in-flight events use #{describe_json_schema_versions(json_schema_versions, "or")}, delete #{files_noun_phrase(json_schema_versions)} from `#{JSON_SCHEMAS_BY_VERSION_DIRECTORY}`, and no further changes are required.
          EOS
        end

        def missing_type_error_for(type, json_schema_versions)
          <<~EOS
            The `#{type}` type (which existed in #{describe_json_schema_versions(json_schema_versions, "and")}) no longer exists in the current schema definition.
            ElasticGraph cannot guess what it should do with this type's data when ingesting events at #{old_versions(json_schema_versions)}.
            To continue, do one of the following:

            1. If the `#{type}` type has been renamed, indicate this by calling `type.renamed_from "#{type}"` on the renamed type.
            2. If the `#{type}` field has been dropped, indicate this by calling `schema.deleted_type "#{type}"` on the schema.
            3. Alternately, if no publishers or in-flight events use #{describe_json_schema_versions(json_schema_versions, "or")}, delete #{files_noun_phrase(json_schema_versions)} from `#{JSON_SCHEMAS_BY_VERSION_DIRECTORY}`, and no further changes are required.
          EOS
        end

        def missing_necessary_field_error_for(field, json_schema_versions)
          path = field.fully_qualified_path.split(".").last
          # :nocov: -- we only cover one side of this ternary.
          has_or_have = (json_schema_versions.size == 1) ? "has" : "have"
          # :nocov:

          <<~EOS
            #{describe_json_schema_versions(json_schema_versions, "and")} #{has_or_have} no field that maps to the #{field.field_type} field path of `#{field.fully_qualified_path}`.
            Since the field path is required for #{field.field_type}, ElasticGraph cannot ingest events that lack it. To continue, do one of the following:

            1. If the `#{field.fully_qualified_path}` field has been renamed, indicate this by calling `field.renamed_from "#{path}"` on the renamed field rather than using `deleted_field`.
            2. Alternately, if no publishers or in-flight events use #{describe_json_schema_versions(json_schema_versions, "or")}, delete #{files_noun_phrase(json_schema_versions)} from `#{JSON_SCHEMAS_BY_VERSION_DIRECTORY}`, and no further changes are required.
          EOS
        end

        def describe_json_schema_versions(json_schema_versions, conjunction)
          json_schema_versions = json_schema_versions.sort

          # Steep doesn't support pattern matching yet, so have to skip type checking here.
          __skip__ = case json_schema_versions
          in [single_version]
            "JSON schema version #{single_version}"
          in [version1, version2]
            "JSON schema versions #{version1} #{conjunction} #{version2}"
          else
            *versions, last_version = json_schema_versions
            "JSON schema versions #{versions.join(", ")}, #{conjunction} #{last_version}"
          end
        end

        def old_versions(json_schema_versions)
          return "this old version" if json_schema_versions.size == 1
          "these old versions"
        end

        def files_noun_phrase(json_schema_versions)
          return "its file" if json_schema_versions.size == 1
          "their files"
        end

        def new_versioned_json_schema_artifact(desired_contents)
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
