# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "did_you_mean"
require "elastic_graph/constants"
require "elastic_graph/schema_definition/json_schema_pruner"
require "elastic_graph/support/memoizable_data"
require "fileutils"
require "graphql"
require "graphql/c_parser"
require "tempfile"
require "yaml"

module ElasticGraph
  module SchemaDefinition
    # Manages schema artifacts. Note: not tested directly. Instead, the `RakeTasks` tests drive this class.
    #
    # Note that we use `abort` instead of `raise` here for exceptions that require the user to perform an action
    # to resolve. The output from `abort` is cleaner (no stack trace, etc) which improves the signal-to-noise
    # ratio for the user to (hopefully) make it easier to understand what to do, without needing to wade through
    # extra output.
    #
    # @private
    class SchemaArtifactManager
      # @dynamic schema_definition_results
      attr_reader :schema_definition_results

      def initialize(schema_definition_results:, schema_artifacts_directory:, enforce_json_schema_version:, output:, max_diff_lines: 50)
        @schema_definition_results = schema_definition_results
        @schema_artifacts_directory = schema_artifacts_directory
        @enforce_json_schema_version = enforce_json_schema_version
        @output = output
        @max_diff_lines = max_diff_lines

        @json_schemas_artifact = new_yaml_artifact(
          JSON_SCHEMAS_FILE,
          JSONSchemaPruner.prune(schema_definition_results.current_public_json_schema),
          extra_comment_lines: [
            "This is the \"public\" JSON schema file and is intended to be provided to publishers so that",
            "they can perform code generation and event validation."
          ]
        )

        # Here we round-trip the SDL string through the GraphQL gem's formatting logic. This provides
        # nice, consistent formatting (alphabetical order, consistent spacing, etc) and also prunes out
        # any "orphaned" schema types (that is, types that are defined but never referenced).
        # We also prepend a line break so there's a blank line between the comment block and the
        # schema elements.
        graphql_schema = ::GraphQL::Schema.from_definition(schema_definition_results.graphql_schema_string).to_definition.chomp

        unversioned_artifacts = [
          new_yaml_artifact(DATASTORE_CONFIG_FILE, schema_definition_results.datastore_config),
          new_yaml_artifact(RUNTIME_METADATA_FILE, pruned_runtime_metadata(graphql_schema).to_dumpable_hash),
          @json_schemas_artifact,
          new_raw_artifact(GRAPHQL_SCHEMA_FILE, "\n" + graphql_schema),
          new_yaml_artifact(DATA_WAREHOUSE_FILE, schema_definition_results.warehouse_config)
        ]

        versioned_artifacts = build_desired_versioned_json_schemas(@json_schemas_artifact.desired_contents).values.map do |versioned_schema|
          new_versioned_json_schema_artifact(versioned_schema)
        end

        @artifacts = (unversioned_artifacts + versioned_artifacts).sort_by(&:file_name)
        notify_about_unused_type_name_overrides
        notify_about_unused_enum_value_overrides
      end

      # Dumps all the schema artifacts to disk.
      def dump_artifacts
        check_if_needs_json_schema_version_bump do |recommended_json_schema_version|
          if @enforce_json_schema_version
            # @type var setter_location: ::Thread::Backtrace::Location
            # We use `_ =` because while `json_schema_version_setter_location` can be nil,
            # it'll never be nil if we get here and we want the type to be non-nilable.
            setter_location = _ = schema_definition_results.json_schema_version_setter_location
            setter_location_path = ::Pathname.new(setter_location.absolute_path.to_s).relative_path_from(::Dir.pwd)

            abort "A change has been attempted to `json_schemas.yaml`, but the `json_schema_version` has not been correspondingly incremented. Please " \
              "increase the schema's version, and then run the `schema_artifacts:dump` command again.\n\n" \
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

        ::FileUtils.mkdir_p(@schema_artifacts_directory)
        @artifacts.each { |artifact| artifact.dump(@output) }
      end

      # Checks that all schema artifacts are up-to-date, raising an exception if not.
      def check_artifacts
        out_of_date_artifacts = @artifacts.select(&:out_of_date?)

        if out_of_date_artifacts.empty?
          descriptions = @artifacts.map.with_index(1) { |art, i| "#{i}. #{art.file_name}" }
          @output.puts <<~EOS
            Your schema artifacts are all up to date:
            #{descriptions.join("\n")}

          EOS
        else
          abort artifacts_out_of_date_error(out_of_date_artifacts)
        end
      end

      private

      def notify_about_unused_type_name_overrides
        type_namer = @schema_definition_results.state.type_namer
        return if (unused_overrides = type_namer.unused_name_overrides).empty?

        suggester = ::DidYouMean::SpellChecker.new(dictionary: type_namer.used_names.to_a)
        warnings = unused_overrides.map.with_index(1) do |(unused_name, _), index|
          alternatives = suggester.correct(unused_name).map { |alt| "`#{alt}`" }
          "#{index}. The type name override `#{unused_name}` does not match any type in your GraphQL schema and has been ignored." \
            "#{" Possible alternatives: #{alternatives.join(", ")}." unless alternatives.empty?}"
        end

        @output.puts <<~EOS
          WARNING: #{unused_overrides.size} of the `type_name_overrides` do not match any type(s) in your GraphQL schema:

          #{warnings.join("\n")}
        EOS
      end

      def notify_about_unused_enum_value_overrides
        enum_value_namer = @schema_definition_results.state.enum_value_namer
        return if (unused_overrides = enum_value_namer.unused_overrides).empty?

        used_value_names_by_type_name = enum_value_namer.used_value_names_by_type_name
        type_suggester = ::DidYouMean::SpellChecker.new(dictionary: used_value_names_by_type_name.keys)
        index = 0
        warnings = unused_overrides.flat_map do |type_name, overrides|
          if used_value_names_by_type_name.key?(type_name)
            value_suggester = ::DidYouMean::SpellChecker.new(dictionary: used_value_names_by_type_name.fetch(type_name))
            overrides.map do |(value_name), _|
              alternatives = value_suggester.correct(value_name).map { |alt| "`#{alt}`" }
              "#{index += 1}. The enum value override `#{type_name}.#{value_name}` does not match any enum value in your GraphQL schema and has been ignored." \
                "#{" Possible alternatives: #{alternatives.join(", ")}." unless alternatives.empty?}"
            end
          else
            alternatives = type_suggester.correct(type_name).map { |alt| "`#{alt}`" }
            ["#{index += 1}. `enum_value_overrides_by_type` has a `#{type_name}` key, which does not match any enum type in your GraphQL schema and has been ignored." \
              "#{" Possible alternatives: #{alternatives.join(", ")}." unless alternatives.empty?}"]
          end
        end

        @output.puts <<~EOS
          WARNING: some of the `enum_value_overrides_by_type` do not match any type(s)/value(s) in your GraphQL schema:

          #{warnings.join("\n")}
        EOS
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

      def artifacts_out_of_date_error(out_of_date_artifacts)
        # @type var diffs: ::Array[[SchemaArtifact[untyped], ::String]]
        diffs = []

        descriptions = out_of_date_artifacts.map.with_index(1) do |artifact, index|
          reason =
            if (diff = artifact.diff(color: @output.tty?))
              description, diff = truncate_diff(diff, @max_diff_lines)
              diffs << [artifact, diff]
              "see [#{diffs.size}] below for the #{description}"
            else
              "file does not exist"
            end

          "#{index}. #{artifact.file_name} (#{reason})"
        end

        diffs = diffs.map.with_index(1) do |(artifact, diff), index|
          <<~EOS
            [#{index}] #{artifact.file_name} diff:
            #{diff}
          EOS
        end

        <<~EOS.strip
          #{out_of_date_artifacts.size} schema artifact(s) are out of date. Run `rake schema_artifacts:dump` to update the following artifact(s):

          #{descriptions.join("\n")}

          #{diffs.join("\n")}
        EOS
      end

      def truncate_diff(diff, lines)
        diff_lines = diff.lines

        if diff_lines.size <= lines
          ["diff", diff]
        else
          truncated = diff_lines.first(lines).join
          ["first #{lines} lines of the diff", truncated]
        end
      end

      def new_yaml_artifact(file_name, desired_contents, extra_comment_lines: [])
        SchemaArtifact.new(
          ::File.join(@schema_artifacts_directory, file_name),
          desired_contents,
          ->(hash) { ::YAML.dump(hash) },
          ->(string) { ::YAML.safe_load(string) },
          extra_comment_lines
        )
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

      def new_raw_artifact(file_name, desired_contents)
        SchemaArtifact.new(
          ::File.join(@schema_artifacts_directory, file_name),
          desired_contents,
          _ = :itself.to_proc,
          _ = :itself.to_proc,
          []
        )
      end

      def check_if_needs_json_schema_version_bump(&block)
        if @json_schemas_artifact.out_of_date?
          existing_schema_version = @json_schemas_artifact.existing_dumped_contents&.dig(JSON_SCHEMA_VERSION_KEY) || -1
          desired_schema_version = @json_schemas_artifact.desired_contents[JSON_SCHEMA_VERSION_KEY]

          if existing_schema_version >= desired_schema_version
            yield existing_schema_version + 1
          end
        end
      end

      def pruned_runtime_metadata(graphql_schema_string)
        schema = ::GraphQL::Schema.from_definition(graphql_schema_string)
        runtime_meta = schema_definition_results.runtime_metadata

        schema_type_names = schema.types.keys
        pruned_enum_types = runtime_meta.enum_types_by_name.slice(*schema_type_names)
        pruned_scalar_types = runtime_meta.scalar_types_by_name.slice(*schema_type_names)
        pruned_object_types = runtime_meta.object_types_by_name.slice(*schema_type_names)

        runtime_meta.with(
          enum_types_by_name: pruned_enum_types,
          scalar_types_by_name: pruned_scalar_types,
          object_types_by_name: pruned_object_types
        )
      end
    end

    # @private
    class SchemaArtifact < Support::MemoizableData.define(:file_name, :desired_contents, :dumper, :loader, :extra_comment_lines)
      def dump(output)
        if out_of_date?
          dirname = File.dirname(file_name)
          FileUtils.mkdir_p(dirname) # Create directory if needed.

          ::File.write(file_name, dumped_contents)
          output.puts "Dumped schema artifact to `#{file_name}`."
        else
          output.puts "`#{file_name}` is already up to date."
        end
      end

      def out_of_date?
        (_ = existing_dumped_contents) != desired_contents
      end

      def existing_dumped_contents
        return nil unless exists?

        # We drop the first 2 lines because it is the comment block containing dynamic elements.
        file_contents = ::File.read(file_name).split("\n").drop(2).join("\n")
        loader.call(file_contents)
      end

      def diff(color:)
        return nil unless exists?

        ::Tempfile.create do |f|
          f.write(dumped_contents.chomp)
          f.fsync

          `git diff --no-index #{file_name} #{f.path}#{" --color" if color}`
            .gsub(file_name, "existing_contents")
            .gsub(f.path, "/updated_contents")
        end
      end

      private

      def exists?
        return !!@exists if defined?(@exists)
        @exists = ::File.exist?(file_name)
      end

      def dumped_contents
        @dumped_contents ||= "#{comment_preamble}\n#{dumper.call(desired_contents)}"
      end

      def comment_preamble
        lines = [
          "Generated by `rake schema_artifacts:dump`.",
          "DO NOT EDIT BY HAND. Any edits will be lost the next time the rake task is run."
        ]

        lines = extra_comment_lines + [""] + lines unless extra_comment_lines.empty?
        lines.map { |line| "# #{line}".strip }.join("\n")
      end
    end
  end
end
