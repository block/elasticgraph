# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/errors"
require "elastic_graph/schema_artifacts/runtime_metadata/schema_element_names"
require "elastic_graph/schema_definition/api"
require "elastic_graph/schema_definition/schema_artifact_manager"

module ElasticGraph
  module SchemaDefinition
    # Mixin designed to facilitate writing tests that define schemas.
    #
    # @private
    module TestSupport
      extend self

      def define_schema(
        schema_element_name_form:,
        schema_element_name_overrides: {},
        index_document_sizes: true,
        json_schema_version: 1,
        extension_modules: [],
        derived_type_name_formats: {},
        type_name_overrides: {},
        enum_value_overrides_by_type: {},
        reload_schema_artifacts: false,
        output: nil,
        &block
      )
        schema_elements = SchemaArtifacts::RuntimeMetadata::SchemaElementNames.new(
          form: schema_element_name_form,
          overrides: schema_element_name_overrides
        )

        define_schema_with_schema_elements(
          schema_elements,
          index_document_sizes: index_document_sizes,
          json_schema_version: json_schema_version,
          extension_modules: extension_modules,
          derived_type_name_formats: derived_type_name_formats,
          type_name_overrides: type_name_overrides,
          enum_value_overrides_by_type: enum_value_overrides_by_type,
          reload_schema_artifacts: reload_schema_artifacts,
          output: output,
          &block
        )
      end

      def define_schema_with_schema_elements(
        schema_elements,
        index_document_sizes: true,
        json_schema_version: 1,
        extension_modules: [],
        derived_type_name_formats: {},
        type_name_overrides: {},
        enum_value_overrides_by_type: {},
        reload_schema_artifacts: false,
        output: nil
      )
        api = API.new(
          schema_elements,
          index_document_sizes,
          extension_modules: extension_modules,
          derived_type_name_formats: derived_type_name_formats,
          type_name_overrides: type_name_overrides,
          enum_value_overrides_by_type: enum_value_overrides_by_type,
          output: output || $stdout
        )

        yield api if block_given?

        # Set the json_schema_version to the provided value, if needed.
        if !json_schema_version.nil? && api.state.json_schema_version.nil?
          api.json_schema_version json_schema_version
        end

        # :nocov: -- the else branch and code past this aren't used by tests in elasticgraph-schema_definition.
        return api.results unless reload_schema_artifacts

        # Reloading the schema artifacts takes extra time that we don't usually want to spend (so it's opt-in)
        # but it can be useful in some cases because there is a bit of extra pruning/validation that it applies.
        tmp_dir = ::Dir.mktmpdir
        artifacts_manager = SchemaDefinition::SchemaArtifactManager.new(
          schema_definition_results: api.results,
          schema_artifacts_directory: tmp_dir,
          enforce_json_schema_version: false,
          output: ::StringIO.new
        )

        artifacts_manager.dump_artifacts

        SchemaArtifacts::FromDisk.new(tmp_dir)
        # :nocov:
      end

      DOC_COMMENTS = (
        '(?:^ *"""\\n' + # opening sequence of `"""` on its own line.
        '(?:[^"]|(?:"(?!")))*' + # any sequence characters with no `""` sequence. (either no `"` or `"` is not followed by another)
        '\\n *"""\\n)' # closing sequence of `"""` on its own line.
      )

      def type_def_from(sdl, type, include_docs: false)
        type_def_keyword = '^(type|input|enum|union|interface|scalar|directive)\b'
        # capture from the start of the type definition for `type` until the next type definition (or `\z` for end of string)
        type_extraction_regex = /(#{DOC_COMMENTS}?#{type_def_keyword} #{type}\b.*?)(?:(?:#{DOC_COMMENTS}?#{type_def_keyword})|\z)/m
        # type_defs = sdl.scan(type_extraction_regex).map(&:first)
        type_defs = sdl.scan(type_extraction_regex).map { |match| [match].flatten.first }

        if type_defs.size >= 2
          # :nocov: -- only executed when a mistake has been made; causes a failing test.
          raise Errors::SchemaError,
            "Expected to find 0 or 1 type definition for #{type}, but found #{type_defs.size}. Type defs:\n\n#{type_defs.join("\n\n")}"
          # :nocov:
        end

        result = type_defs.first&.strip
        result &&= strip_docs(result) unless include_docs
        result
      end

      def strip_docs(string)
        string
          .gsub(/#{DOC_COMMENTS}/o, "") # strip doc comments
          .gsub("\n\n", "\n") # cleanup formatting so we don't have extra blank lines.
      end
    end
  end
end
