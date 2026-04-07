# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/json_ingestion/schema_definition/schema_artifact_manager_extension"
require "stringio"
require "tmpdir"

module ElasticGraph
  module JSONIngestion
    module SchemaDefinition
      RSpec.describe SchemaArtifactManagerExtension do
        let(:yaml_artifact_class) do
          ::Data.define(
            :path,
            :desired_contents,
            :existing_dumped_contents,
            :out_of_date_value,
            :extra_comment_lines
          ) do
            def out_of_date?
              out_of_date_value
            end
          end
        end

        let(:deprecated_element_class) do
          ::Data.define(:name, :description, :defined_at)
        end

        let(:defined_at_class) do
          ::Data.define(:path, :lineno)
        end

        let(:missing_necessary_field_class) do
          ::Data.define(:fully_qualified_path, :field_type)
        end

        let(:merged_schema_class) do
          ::Data.define(
            :json_schema_version,
            :json_schema,
            :missing_fields,
            :missing_types,
            :missing_necessary_fields,
            :definition_conflicts
          )
        end

        let(:fake_manager_results_class) do
          ::Class.new do
            attr_accessor :current_public_json_schema, :json_schema_version_setter_location, :unused_deprecated_elements

            def merge_field_metadata_into_json_schema(_json_schema)
            end
          end
        end

        def build_manager(schema_definition_results:, enforce_json_schema_version:, schema_artifacts_directory:, artifacts_by_path:, output:)
          yaml_artifact_class = self.yaml_artifact_class

          base_class = ::Class.new do
            attr_reader :schema_definition_results, :new_yaml_artifact_calls

            def initialize(schema_definition_results, enforce_json_schema_version, schema_artifacts_directory, artifacts_by_path, output)
              @schema_definition_results = schema_definition_results
              @enforce_json_schema_version = enforce_json_schema_version
              @schema_artifacts_directory = schema_artifacts_directory
              @artifacts_by_path = artifacts_by_path
              @output = output
              @new_yaml_artifact_calls = []
            end

            def dump_artifacts
              :base_dump
            end

            private

            def artifacts_from_schema_def
              [:base_artifact]
            end

            define_method(:new_yaml_artifact) do |path, contents, extra_comment_lines:|
              @new_yaml_artifact_calls << {
                path: path,
                contents: contents,
                extra_comment_lines: extra_comment_lines
              }

              @artifacts_by_path.fetch(path) do
                yaml_artifact_class.new(
                  path: path,
                  desired_contents: contents,
                  existing_dumped_contents: nil,
                  out_of_date_value: false,
                  extra_comment_lines: extra_comment_lines
                )
              end
            end
          end

          ::Class.new(base_class) do
            prepend SchemaArtifactManagerExtension
          end.new(
            schema_definition_results,
            enforce_json_schema_version,
            schema_artifacts_directory,
            artifacts_by_path,
            output
          )
        end

        before do
          allow(ElasticGraph::JSONIngestion::SchemaDefinition::JSONSchemaPruner).to receive(:prune) { |json_schema| json_schema }
        end

        it "warns when a version bump is needed but enforcement is disabled" do
          output = ::StringIO.new
          public_schema = {JSON_SCHEMA_VERSION_KEY => 2}
          artifact = yaml_artifact_class.new(
            path: JSON_SCHEMAS_FILE,
            desired_contents: public_schema,
            existing_dumped_contents: {JSON_SCHEMA_VERSION_KEY => 2},
            out_of_date_value: true,
            extra_comment_lines: []
          )
          results = instance_double(fake_manager_results_class, current_public_json_schema: public_schema, unused_deprecated_elements: [])

          manager = build_manager(
            schema_definition_results: results,
            enforce_json_schema_version: false,
            schema_artifacts_directory: ::Dir.mktmpdir,
            artifacts_by_path: {JSON_SCHEMAS_FILE => artifact},
            output: output
          )

          expect(manager.dump_artifacts).to eq(:base_dump)
          expect(output.string).to include("WARNING: the `json_schemas.yaml` artifact is being updated")
        end

        it "aborts when a version bump is needed and enforcement is enabled" do
          output = ::StringIO.new
          public_schema = {JSON_SCHEMA_VERSION_KEY => 2}
          artifact = yaml_artifact_class.new(
            path: JSON_SCHEMAS_FILE,
            desired_contents: public_schema,
            existing_dumped_contents: {JSON_SCHEMA_VERSION_KEY => 2},
            out_of_date_value: true,
            extra_comment_lines: []
          )
          location = instance_double(::Thread::Backtrace::Location, absolute_path: __FILE__, lineno: 123)
          results = instance_double(
            fake_manager_results_class,
            current_public_json_schema: public_schema,
            json_schema_version_setter_location: location,
            unused_deprecated_elements: []
          )

          manager = build_manager(
            schema_definition_results: results,
            enforce_json_schema_version: true,
            schema_artifacts_directory: ::Dir.mktmpdir,
            artifacts_by_path: {JSON_SCHEMAS_FILE => artifact},
            output: output
          )
          manager.define_singleton_method(:abort) do |message|
            raise message
          end

          expect {
            manager.dump_artifacts
          }.to raise_error(RuntimeError, /schema\.json_schema_version 3/)
        end

        it "yields only when a dumped schema is out of date and its version is not newer" do
          output = ::StringIO.new
          manager = build_manager(
            schema_definition_results: instance_double(fake_manager_results_class),
            enforce_json_schema_version: false,
            schema_artifacts_directory: ::Dir.mktmpdir,
            artifacts_by_path: {},
            output: output
          )

          current_artifact = yaml_artifact_class.new(
            path: JSON_SCHEMAS_FILE,
            desired_contents: {JSON_SCHEMA_VERSION_KEY => 2},
            existing_dumped_contents: {JSON_SCHEMA_VERSION_KEY => 2},
            out_of_date_value: true,
            extra_comment_lines: []
          )
          manager.define_singleton_method(:json_schemas_artifact) { current_artifact }

          yielded_versions = []
          manager.send(:check_if_needs_json_schema_version_bump) do |recommended_version|
            yielded_versions << recommended_version
          end
          expect(yielded_versions).to eq([3])

          clean_artifact = yaml_artifact_class.new(
            path: JSON_SCHEMAS_FILE,
            desired_contents: {JSON_SCHEMA_VERSION_KEY => 3},
            existing_dumped_contents: nil,
            out_of_date_value: false,
            extra_comment_lines: []
          )
          manager.define_singleton_method(:json_schemas_artifact) { clean_artifact }

          expect {
            manager.send(:check_if_needs_json_schema_version_bump) { raise "should not yield" }
          }.not_to raise_error
        end

        it "builds public and versioned JSON schema artifacts alongside base artifacts" do
          output = ::StringIO.new
          schema_artifacts_directory = ::Dir.mktmpdir
          ::Dir.mkdir(::File.join(schema_artifacts_directory, JSON_SCHEMAS_BY_VERSION_DIRECTORY))
          ::File.write(
            ::File.join(schema_artifacts_directory, JSON_SCHEMAS_BY_VERSION_DIRECTORY, "v1.yaml"),
            <<~YAML
              ---
              json_schema_version: 1
            YAML
          )

          public_schema = {JSON_SCHEMA_VERSION_KEY => 2}
          merged_v1 = merged_schema_class.new(
            json_schema_version: 1,
            json_schema: {JSON_SCHEMA_VERSION_KEY => 1},
            missing_fields: [],
            missing_types: [],
            missing_necessary_fields: [],
            definition_conflicts: []
          )
          merged_v2 = merged_schema_class.new(
            json_schema_version: 2,
            json_schema: {JSON_SCHEMA_VERSION_KEY => 2},
            missing_fields: [],
            missing_types: [],
            missing_necessary_fields: [],
            definition_conflicts: []
          )

          results = instance_double(
            fake_manager_results_class,
            current_public_json_schema: public_schema,
            merge_field_metadata_into_json_schema: nil,
            unused_deprecated_elements: []
          )
          expect(results).to receive(:merge_field_metadata_into_json_schema).with({JSON_SCHEMA_VERSION_KEY => 1}).and_return(merged_v1)
          expect(results).to receive(:merge_field_metadata_into_json_schema).with(public_schema).and_return(merged_v2)

          manager = build_manager(
            schema_definition_results: results,
            enforce_json_schema_version: false,
            schema_artifacts_directory: schema_artifacts_directory,
            artifacts_by_path: {},
            output: output
          )

          artifacts = manager.send(:artifacts_from_schema_def)

          expect(artifacts.first).to eq(:base_artifact)
          expect(artifacts.drop(1).map(&:path)).to contain_exactly(
            JSON_SCHEMAS_FILE,
            ::File.join(JSON_SCHEMAS_BY_VERSION_DIRECTORY, "v1.yaml"),
            ::File.join(JSON_SCHEMAS_BY_VERSION_DIRECTORY, "v2.yaml")
          )
          expect(manager.new_yaml_artifact_calls.map { |call| call[:path] }).to include(
            JSON_SCHEMAS_FILE,
            ::File.join(JSON_SCHEMAS_BY_VERSION_DIRECTORY, "v1.yaml"),
            ::File.join(JSON_SCHEMAS_BY_VERSION_DIRECTORY, "v2.yaml")
          )
        end

        it "reports merge errors for missing fields, missing types, missing necessary fields, and conflicts" do
          output = ::StringIO.new
          manager = build_manager(
            schema_definition_results: instance_double(fake_manager_results_class, unused_deprecated_elements: []),
            enforce_json_schema_version: false,
            schema_artifacts_directory: ::Dir.mktmpdir,
            artifacts_by_path: {},
            output: output
          )
          manager.define_singleton_method(:abort) do |message|
            raise message
          end

          missing_necessary_field = missing_necessary_field_class.new(
            fully_qualified_path: "Widget.metadata.currency",
            field_type: "routing"
          )
          conflict_a = deprecated_element_class.new(
            name: "Widget",
            description: "schema.object_type \"Widget\"",
            defined_at: defined_at_class.new(path: "config/schema/widget.rb", lineno: 12)
          )
          conflict_b = deprecated_element_class.new(
            name: "Widget",
            description: "schema.deleted_type \"Widget\"",
            defined_at: defined_at_class.new(path: "config/schema/deleted_widget.rb", lineno: 4)
          )
          merged_result = merged_schema_class.new(
            json_schema_version: 3,
            json_schema: {JSON_SCHEMA_VERSION_KEY => 3},
            missing_fields: ["Widget.old_name"],
            missing_types: ["OldWidget"],
            missing_necessary_fields: [missing_necessary_field],
            definition_conflicts: [conflict_a, conflict_b]
          )

          expect {
            manager.send(:report_json_schema_merge_errors, [merged_result])
          }.to raise_error(
            RuntimeError,
            /field\.renamed_from "old_name".*schema\.deleted_type "OldWidget".*field has been renamed.*The schema definition of `Widget` has conflicts/m
          )
        end

        it "reports warnings for unused deprecated elements" do
          output = ::StringIO.new
          unused_a = deprecated_element_class.new(
            name: "Widget",
            description: "schema.deleted_field \"old_name\"",
            defined_at: defined_at_class.new(path: "config/schema/widget.rb", lineno: 20)
          )
          unused_b = deprecated_element_class.new(
            name: "Widget",
            description: "schema.deleted_type \"LegacyWidget\"",
            defined_at: defined_at_class.new(path: "config/schema/legacy_widget.rb", lineno: 5)
          )
          results = instance_double(fake_manager_results_class, unused_deprecated_elements: [unused_a, unused_b])
          manager = build_manager(
            schema_definition_results: results,
            enforce_json_schema_version: false,
            schema_artifacts_directory: ::Dir.mktmpdir,
            artifacts_by_path: {},
            output: output
          )

          manager.send(:report_json_schema_merge_warnings)

          expect(output.string).to include(
            "The schema definition has 2 unneeded reference(s) to deprecated schema elements.",
            "1. schema.deleted_type \"LegacyWidget\"",
            "2. schema.deleted_field \"old_name\""
          )
        end

        it "formats JSON schema version descriptions and noun helpers" do
          output = ::StringIO.new
          manager = build_manager(
            schema_definition_results: instance_double(fake_manager_results_class, unused_deprecated_elements: []),
            enforce_json_schema_version: false,
            schema_artifacts_directory: ::Dir.mktmpdir,
            artifacts_by_path: {},
            output: output
          )

          expect(manager.send(:describe_json_schema_versions, [7], "and")).to eq("JSON schema version 7")
          expect(manager.send(:describe_json_schema_versions, [7, 8], "and")).to eq("JSON schema versions 7 and 8")
          expect(manager.send(:describe_json_schema_versions, [7, 8, 9], "or")).to eq("JSON schema versions 7, 8, or 9")
          expect(manager.send(:old_versions, [7])).to eq("this old version")
          expect(manager.send(:old_versions, [7, 8])).to eq("these old versions")
          expect(manager.send(:files_noun_phrase, [7])).to eq("its file")
          expect(manager.send(:files_noun_phrase, [7, 8])).to eq("their files")
        end
      end
    end
  end
end
