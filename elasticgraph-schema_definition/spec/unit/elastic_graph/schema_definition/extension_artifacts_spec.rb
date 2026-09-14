# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/json_ingestion/schema_definition/api_extension"
require "elastic_graph/schema_artifacts/from_disk"
require "elastic_graph/schema_definition/test_support"

require_relative "../../../fixtures/custom_artifacts/api_extension"

module ElasticGraph
  module SchemaDefinition
    RSpec.describe "Extension-owned schema artifacts" do
      it "loads custom artifacts without enabling a bundled ingestion format", :in_temp_dir do
        results = TestSupport.define_schema(
          schema_element_name_form: :snake_case,
          extension_modules: [TestSupport::APIExtension, CustomArtifactsExample::APIExtension]
        ) do |schema|
          schema.object_type "Widget" do |type|
            type.field "id", "ID!"
            type.index "widgets"
          end
        end
        results.state.factory.new_schema_artifact_manager(
          schema_definition_results: results, schema_artifacts_directory: Dir.pwd, output: StringIO.new
        ).dump_artifacts

        [results, SchemaArtifacts::FromDisk.new(Dir.pwd)].each do |artifacts|
          expect(artifacts.extension_artifacts.fetch("example/custom").type_names).to include("Widget")
          expect(artifacts.extension_artifacts.key?("json")).to be false
          expect(artifacts.extension_artifacts.key?("proto")).to be false
        end
      end

      it "round-trips a custom provider and its configuration alongside JSON", :in_temp_dir do
        results = TestSupport.define_schema(
          schema_element_name_form: :snake_case,
          path_to_schema: File.join(Dir.pwd, "schema.rb"),
          extension_modules: [CustomArtifactsExample::APIExtension, JSONIngestion::SchemaDefinition::APIExtension]
        ) do |schema|
          schema.json_schema_version 1
          schema.object_type "Widget" do |type|
            type.field "id", "ID!"
            type.index "widgets"
          end
        end
        results.state.factory.new_schema_artifact_manager(
          schema_definition_results: results, schema_artifacts_directory: Dir.pwd, output: StringIO.new
        ).dump_artifacts
        # A service can use one extension without installing every provider named in its artifacts.
        metadata = YAML.safe_load_file(RUNTIME_METADATA_FILE)
        metadata.fetch("schema_artifact_extensions")["example/uninstalled"] = {
          "extension_ref" => {"name" => "UninstalledProvider", "require_path" => "uninstalled/provider"}
        }
        File.write(RUNTIME_METADATA_FILE, YAML.dump(metadata))
        disk = SchemaArtifacts::FromDisk.new(Dir.pwd)
        expect(disk.extension_artifacts.key?("example/uninstalled")).to be true

        [results, disk].each do |artifacts|
          expect(artifacts.extension_artifacts.key?("example/custom")).to be true
          custom = artifacts.extension_artifacts.fetch("example/custom")
          expect(custom.type_names).to include("Widget")
          expect(custom.label).to eq "custom format"
          expect(custom).to eq results.extension_artifacts.fetch("example/custom")
          expect(artifacts.extension_artifacts.fetch("example/custom")).to be custom
          json = artifacts.extension_artifacts.fetch("json")
          expect(json.available_json_schema_versions).to eq Set[1]
          expect(json.json_schemas_for(1).fetch("$defs").fetch("Widget")).to eq results.extension_artifacts.fetch("json").json_schemas_for(1).fetch("$defs").fetch("Widget")
          expect(artifacts).not_to respond_to(:json_schemas_for)
        end
      end

      it "keeps provider configuration and caches local to each schema instance" do
        results = ["first", "second"].map do |label|
          TestSupport.define_schema(schema_element_name_form: :snake_case) do |schema|
            schema.register_schema_artifact_extension "example/custom", CustomArtifactsExample::Artifacts,
              defined_at: File.expand_path("../../../fixtures/custom_artifacts/provider.rb", __dir__), label: label
          end
        end

        first, second = results.map { |schema| schema.extension_artifacts.fetch("example/custom") }
        expect(first.label).to eq "first"
        expect(second.label).to eq "second"
        expect(first).not_to be second
        expect(results.first.extension_artifacts.fetch("example/custom")).to be first
      end

      it "reports absent extensions consistently for disk and in-memory artifacts", :in_temp_dir do
        results = TestSupport.define_schema(schema_element_name_form: :snake_case)
        File.write(RUNTIME_METADATA_FILE, YAML.dump(results.runtime_metadata.to_dumpable_hash))

        [results, SchemaArtifacts::FromDisk.new(Dir.pwd)].each do |artifacts|
          expect(artifacts.extension_artifacts.key?("example/missing")).to be false
          expect {
            artifacts.extension_artifacts.fetch("example/missing")
          }.to raise_error Errors::MissingSchemaArtifactError, a_string_including("example/missing", "regenerate")
        end
      end

      it "rejects duplicate provider names" do
        expect {
          TestSupport.define_schema(schema_element_name_form: :snake_case, extension_modules: [CustomArtifactsExample::APIExtension]) do |schema|
            schema.register_schema_artifact_extension "example/custom", CustomArtifactsExample::Artifacts, defined_at: __FILE__
          end
        }.to raise_error Errors::SchemaError, a_string_including("already registered", "example/custom")
      end

      it "rejects factories without both storage implementations" do
        expect {
          TestSupport.define_schema(schema_element_name_form: :snake_case) do |schema|
            schema.register_schema_artifact_extension "example/broken", Enumerable, defined_at: "set"
          end
        }.to raise_error Errors::InvalidExtensionError, a_string_including("from_disk", "from_schema_definition")
      end
    end
  end
end
