# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/constants"
require "elastic_graph/errors"
require "elastic_graph/schema_artifacts/from_disk"

module ElasticGraph
  module SchemaArtifacts
    RSpec.describe SchemaArtifacts, ".from_parsed_yaml" do
      it "uses the `schema_artifacts.directory` setting to build a `FromDisk` instance" do
        artifacts = from_parsed_yaml({"schema_artifacts" => {"directory" => "some_dir"}})

        expect(artifacts).to be_a(FromDisk)
        expect(artifacts.artifacts_dir).to eq "some_dir"
      end

      it "fails with a clear error if the required keys are missing" do
        expect {
          from_parsed_yaml({})
        }.to raise_error Errors::ConfigError, a_string_including("schema_artifacts")

        expect {
          from_parsed_yaml({"schema_artifacts" => {}})
        }.to raise_error Errors::ConfigError, a_string_including("schema_artifacts.directory")
      end

      it "fails with a clear error if extra `schema_artifacts` settings are provided" do
        expect {
          from_parsed_yaml({"schema_artifacts" => {"directory" => "a", "foo" => 3}})
        }.to raise_error Errors::ConfigError, a_string_including("foo")
      end

      def from_parsed_yaml(parsed_yaml, for_context: :graphql)
        SchemaArtifacts.from_parsed_yaml(parsed_yaml, for_context: for_context)
      end
    end

    RSpec.describe FromDisk do
      it "loads each schema artifact from disk" do
        artifacts = FromDisk.new(::File.join(CommonSpecHelpers::REPO_ROOT, "config", "schema", "artifacts"), :graphql)

        expect_artifacts_to_load_and_be_valid(artifacts)
        expect(artifacts.datastore_scripts.values.first).to include("context", "script")
      end

      context "with multiple json schemas", :in_temp_dir do
        let(:artifacts) { FromDisk.new(Dir.pwd, :indexer) }

        before do
          ::FileUtils.mkdir_p(JSON_SCHEMAS_BY_VERSION_DIRECTORY)
          ::File.write(::File.join(JSON_SCHEMAS_BY_VERSION_DIRECTORY, "v1.yaml"), ::YAML.dump(JSON_SCHEMA_VERSION_KEY => 1))
          ::File.write(::File.join(JSON_SCHEMAS_BY_VERSION_DIRECTORY, "v2.yaml"), ::YAML.dump(JSON_SCHEMA_VERSION_KEY => 2))
        end

        it "retrieves the specified version of the json_schema" do
          expect(artifacts.json_schemas_for(1)).to include(JSON_SCHEMA_VERSION_KEY => 1)
          expect(artifacts.json_schemas_for(2)).to include(JSON_SCHEMA_VERSION_KEY => 2)
        end

        it "lists the available json_schema_versions" do
          available_versions = artifacts.available_json_schema_versions
          expect(available_versions).to include(1, 2) # We don't want test to keep breaking as new versions are added, so don't assert an exact match.
          expect(available_versions).not_to include(nil) # No `nil` values should be present.
        end

        it "raises if an unavailable json_schema version is requested" do
          expect {
            artifacts.json_schemas_for(9999)
          }.to raise_error Errors::MissingSchemaArtifactError, a_string_including("is not available", "Available versions: 1, 2")
        end

        it "returns the largest JSON schema version as the `latest_json_schema_version`" do
          expect(artifacts.latest_json_schema_version).to eq 2
        end
      end

      context "before any artifacts have been dumped", :in_temp_dir do
        let(:artifacts) { FromDisk.new(Dir.pwd, :graphql) }

        it "raises an error when accessing missing artifacts is attempted" do
          expect { artifacts.graphql_schema_string }.to raise_missing_artifacts_error
          expect { artifacts.indices }.to raise_missing_artifacts_error
          expect { artifacts.datastore_scripts }.to raise_missing_artifacts_error
          expect { artifacts.runtime_metadata }.to raise_missing_artifacts_error
        end

        it "returns an empty set from `available_json_schema_versions`" do
          expect(artifacts.available_json_schema_versions).to eq Set.new
        end

        it "raises an error from `latest_json_schema_version`" do
          expect { artifacts.latest_json_schema_version }.to raise_missing_artifacts_error
        end

        def raise_missing_artifacts_error
          raise_error Errors::MissingSchemaArtifactError, a_string_including("could not be found", artifacts.artifacts_dir)
        end
      end

      describe "#index_mappings_by_index_def_name" do
        let(:artifacts) { FromDisk.new(::File.join(CommonSpecHelpers::REPO_ROOT, "config", "schema", "artifacts"), :indexer) }

        it "returns the index mappings" do
          mappings = artifacts.index_mappings_by_index_def_name

          expect(mappings.keys).to match_array(artifacts.indices.keys + artifacts.index_templates.keys)
          expect(artifacts.indices.dig("addresses", "mappings", "properties", "timestamps", "properties", "created_at")).to eq({
            "type" => "date",
            "format" => DATASTORE_DATE_TIME_FORMAT
          })
          expect(mappings.dig("addresses", "properties", "timestamps", "properties", "created_at")).to eq({
            "type" => "date",
            "format" => DATASTORE_DATE_TIME_FORMAT
          })
        end

        it "is memoized to avoid re-computing the mappings" do
          mappings1 = artifacts.index_mappings_by_index_def_name
          mappings2 = artifacts.index_mappings_by_index_def_name

          expect(mappings1).to be(mappings2)
        end
      end

      def expect_artifacts_to_load_and_be_valid(artifacts)
        expect(artifacts.graphql_schema_string).to include("type Query {")
        expect(artifacts.json_schemas_for(1)).to include("$schema" => JSON_META_SCHEMA)
        expect(artifacts.datastore_config).to include("indices", "index_templates", "scripts")
        expect(artifacts.runtime_metadata).to be_a RuntimeMetadata::Schema

        artifacts.runtime_metadata.scalar_types_by_name.values.each do |scalar_type|
          expect(scalar_type.load_coercion_adapter).not_to be_nil
          expect(scalar_type.load_indexing_preparer).not_to be_nil
        end
      end
    end
  end
end
