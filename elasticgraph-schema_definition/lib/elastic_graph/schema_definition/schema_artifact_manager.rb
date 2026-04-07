# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "did_you_mean"
require "elastic_graph/constants"
require "elastic_graph/support/graphql_gem_loader"
require "elastic_graph/support/memoizable_data"
require "fileutils"
require "tempfile"
require "yaml"

ElasticGraph::Support::GraphQLGemLoader.load

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
      end

      # Dumps all the schema artifacts to disk.
      def dump_artifacts
        ::FileUtils.mkdir_p(@schema_artifacts_directory)
        artifacts.each { |artifact| artifact.dump(@output) }
      end

      # Checks that all schema artifacts are up-to-date, raising an exception if not.
      def check_artifacts
        out_of_date_artifacts = artifacts.select(&:out_of_date?)

        if out_of_date_artifacts.empty?
          descriptions = artifacts.map.with_index(1) { |art, i| "#{i}. #{art.file_name}" }
          @output.puts <<~EOS
            Your schema artifacts are all up to date:
            #{descriptions.join("\n")}

          EOS
        else
          abort artifacts_out_of_date_error(out_of_date_artifacts)
        end
      end

      private

      def artifacts
        @artifacts ||= artifacts_from_schema_def.sort_by(&:file_name).tap do
          # This must be deferred until artifacts are generated, as we can't fully detect
          # unused things until after we've used things to generate artifacts.
          notify_about_unused_type_name_overrides
          notify_about_unused_enum_value_overrides
        end
      end

      # Defined to offer a convenient method to override in an extension in order to add a new schema artifact.
      def artifacts_from_schema_def
        # Here we round-trip the SDL string through the GraphQL gem's formatting logic. This provides
        # nice, consistent formatting (alphabetical order, consistent spacing, etc) and also prunes out
        # any "orphaned" schema types (that is, types that are defined but never referenced).
        # We also prepend a line break so there's a blank line between the comment block and the
        # schema elements.
        graphql_schema = ::GraphQL::Schema.from_definition(schema_definition_results.graphql_schema_string).to_definition.chomp

        [
          new_yaml_artifact(DATASTORE_CONFIG_FILE, schema_definition_results.datastore_config),
          new_yaml_artifact(RUNTIME_METADATA_FILE, pruned_runtime_metadata(graphql_schema).to_dumpable_hash),
          new_raw_artifact(GRAPHQL_SCHEMA_FILE, "\n" + graphql_schema)
        ]
      end

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
          #{out_of_date_artifacts.size} schema artifact(s) are out of date. Run `bundle exec rake schema_artifacts:dump` to update the following artifact(s):

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

      def new_raw_artifact(file_name, desired_contents)
        SchemaArtifact.new(
          ::File.join(@schema_artifacts_directory, file_name),
          desired_contents,
          _ = :itself.to_proc,
          _ = :itself.to_proc,
          []
        )
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
          "Generated by `bundle exec rake schema_artifacts:dump`.",
          "DO NOT EDIT BY HAND. Any edits will be lost the next time the rake task is run."
        ]

        lines = extra_comment_lines + [""] + lines unless extra_comment_lines.empty?
        lines.map { |line| "# #{line}".strip }.join("\n")
      end
    end
  end
end
