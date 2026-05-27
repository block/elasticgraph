# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/constants"

module ElasticGraph
  module JSONIngestion
    module SchemaDefinition
      # Formats and reports JSON schema metadata merge diagnostics.
      #
      # @private
      class JSONSchemaMergeReporter
        def initialize(output)
          @output = output
        end

        def report_errors(merged_results)
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

        def report_warnings(unused_elements)
          return if unused_elements.empty?

          @output.puts <<~EOS
            The schema definition has #{unused_elements.size} unneeded reference(s) to deprecated schema elements. These can all be safely deleted:

            #{format_deprecated_elements(unused_elements)}

          EOS
        end

        private

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
            2. If the `#{type}` type has been dropped, indicate this by calling `schema.deleted_type "#{type}"` on the schema.
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

          case json_schema_versions.size
          when 1
            "JSON schema version #{json_schema_versions.first}"
          when 2
            "JSON schema versions #{json_schema_versions.first} #{conjunction} #{json_schema_versions.last}"
          else
            versions = json_schema_versions.take(json_schema_versions.size - 1)
            "JSON schema versions #{versions.join(", ")}, #{conjunction} #{json_schema_versions.last}"
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
      end
    end
  end
end
