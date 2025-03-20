# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/errors"
require "elastic_graph/schema_definition/scripting/script"
require "elastic_graph/support/memoizable_data"
require "pathname"

module ElasticGraph
  module SchemaDefinition
    # @private
    module Scripting
      # A simple abstraction that supports loading static scripts off of disk. The given directory
      # is expected to have a sub-directory per script context, with individual scripts under the
      # context sub-directories. The language is inferred from the script file extensions.
      #
      # @private
      class FileSystemRepository < Support::MemoizableData.define(:dir)
        # Based on https://www.elastic.co/guide/en/elasticsearch/reference/8.5/modules-scripting.html
        SUPPORTED_LANGUAGES_BY_EXTENSION = {
          ".painless" => "painless",
          ".expression" => "expression",
          ".mustache" => "mustache",
          ".java" => "java"
        }

        # The `Script` objects available in this file system repository.
        def scripts
          @scripts ||= ::Pathname.new(dir).children.sort.flat_map do |context_dir|
            unless context_dir.directory?
              raise Errors::InvalidScriptDirectoryError, "`#{dir}` has a file (#{context_dir}) that is not a context directory as expected."
            end

            context_dir.children.sort.map do |script_file|
              unless script_file.file?
                raise Errors::InvalidScriptDirectoryError, "`#{dir}` has extra directory nesting (#{script_file}) that is unexpected."
              end

              language = SUPPORTED_LANGUAGES_BY_EXTENSION[script_file.extname] || raise(
                Errors::InvalidScriptDirectoryError, "`#{dir}` has a file (`#{script_file}`) that has an unrecognized file extension: #{script_file.extname}."
              )

              Script.new(
                name: script_file.basename.sub_ext("").to_s,
                source: script_file.read.strip,
                language: language,
                context: context_dir.basename.to_s
              )
            end
          end.tap { |all_scripts| verify_no_duplicates!(all_scripts) }
        end

        # Map of script ids keyed by the `scoped_name` to allow easy lookup of the ids.
        def script_ids_by_scoped_name
          @script_ids_by_scoped_name ||= scripts.to_h { |s| [s.scoped_name, s.id] }
        end

        private

        def verify_no_duplicates!(scripts)
          duplicate_scoped_names = scripts.group_by(&:scoped_name).select do |scoped_name, scripts_with_scoped_name|
            scripts_with_scoped_name.size > 1
          end.keys

          if duplicate_scoped_names.any?
            raise Errors::InvalidScriptDirectoryError, "`#{dir}` has multiple scripts with the same scoped name, which is not allowed: #{duplicate_scoped_names.join(", ")}."
          end
        end
      end
    end
  end
end
