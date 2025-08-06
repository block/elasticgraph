# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/schema_definition/scripting/file_system_repository"

module ElasticGraph
  module SchemaDefinition
    module Scripting
      RSpec.describe FileSystemRepository do
        it "loads scripts in multiple supported languages from a directory, treating sub-dirs as script contexts" do
          repo = repo_for_fixture_dir("multiple_contexts_and_languages")

          expect(repo.scripts).to contain_exactly(
            by_age = Script.new(
              name: "by_age",
              source: "// Painless code would go here.",
              language: "painless",
              context: "filter"
            ),
            using_math = Script.new(
              name: "UsingMath",
              source: "// Java code would go here.",
              language: "java",
              context: "filter"
            ),
            by_edit_distance = Script.new(
              name: "by_edit_distance",
              source: "// Lucene expression syntax would go here.",
              language: "expression",
              context: "score"
            ),
            template1 = Script.new(
              name: "template1",
              source: "{{! mustache code would go here}}",
              language: "mustache",
              context: "update"
            )
          )

          expect(repo.script_ids_by_scoped_name).to eq({
            "filter/by_age" => by_age.id,
            "filter/UsingMath" => using_math.id,
            "score/by_edit_distance" => by_edit_distance.id,
            "update/template1" => template1.id
          })
        end

        it "memoizes the script state to avoid re-doing the same I/O over again" do
          repo = repo_for_fixture_dir("multiple_contexts_and_languages")

          scripts = repo.scripts
          script_ids_by_scoped_name = repo.script_ids_by_scoped_name

          expect(repo.scripts).to be(scripts)
          expect(repo.script_ids_by_scoped_name).to be(script_ids_by_scoped_name)
        end

        it "provides a clear error when a file has an extension it doesn't support" do
          repo = repo_for_fixture_dir("unsupported_language")

          expect {
            repo.scripts
          }.to raise_error Errors::InvalidScriptDirectoryError, a_string_including("unrecognized file extension", ".rb")
        end

        it "provides a clear error when the given directory has script files not nested in a context sub-dir" do
          repo = repo_for_fixture_dir("unnested_script_files")

          expect {
            repo.scripts
          }.to raise_error Errors::InvalidScriptDirectoryError, a_string_including("not a context directory as expected", "by_age.painless")
        end

        it "provides a clear error when the given directory has script files not nested in a context sub-dir" do
          repo = repo_for_fixture_dir("double_nested_script_files")

          expect {
            repo.scripts
          }.to raise_error Errors::InvalidScriptDirectoryError, a_string_including("extra directory nesting", "/filter/filter")
        end

        it "provides a clear error when multiple scripts exist with the same name in the same context (but with a different language extension)" do
          repo = repo_for_fixture_dir("duplicate_name_with_different_lang")

          expect {
            repo.scripts
          }.to raise_error Errors::InvalidScriptDirectoryError, a_string_including("multiple scripts with the same scoped name", "filter/by_age")
        end

        it "allows a script name to be reused for a different context" do
          repo = repo_for_fixture_dir("duplicate_name_in_different_contexts")

          expect(repo.scripts).to contain_exactly(
            filter_by_age = Script.new(
              name: "by_age",
              source: "// Painless code would go here.",
              language: "painless",
              context: "filter"
            ),
            update_by_age = Script.new(
              name: "by_age",
              source: "// Painless code would go here.",
              language: "painless",
              context: "update"
            )
          )

          expect(repo.script_ids_by_scoped_name).to eq({
            "filter/by_age" => filter_by_age.id,
            "update/by_age" => update_by_age.id
          })
        end

        it "winds up with a different `id` for two scripts that are the same except for the `context`" do
          repo = repo_for_fixture_dir("duplicate_name_in_different_contexts")

          expect(repo.scripts.map(&:source)).to all eq("// Painless code would go here.")
          expect(repo.scripts.map(&:name)).to all eq("by_age")
          expect(repo.scripts.map(&:language)).to all eq("painless")
          expect(repo.scripts.map(&:context)).to contain_exactly("filter", "update")

          expect(repo.scripts.first.id).not_to eq(repo.scripts.last.id)
          expect(repo.scripts.map(&:id)).to contain_exactly(
            a_string_starting_with("update_by_age_"),
            a_string_starting_with("filter_by_age_")
          )
        end

        def repo_for_fixture_dir(dir_name)
          FileSystemRepository.new(::File.join(FIXTURE_DIR, dir_name))
        end
      end
    end
  end
end
