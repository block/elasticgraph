# Copyright 2024 - 2026 Block, Inc.
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
    RSpec.describe FromDisk do
      it "loads each schema artifact from disk" do
        artifacts = FromDisk.new(::File.join(CommonSpecHelpers::REPO_ROOT, "config", "schema", "artifacts"))

        expect_artifacts_to_load_and_be_valid(artifacts)
        expect(artifacts.datastore_scripts.values.first).to include("context", "script")
        expect(artifacts.extension_artifacts.key?("json")).to be true
      end

      it "loads an extension provider from its runtime metadata", :in_temp_dir do
        registration = RuntimeMetadata::ComponentExtension.new(extension_ref: {
          "name" => "ElasticGraph::Extensions::ArtifactFactory",
          "require_path" => "support/example_extensions/artifact_factory"
        })
        artifacts = FromDisk.new(Dir.pwd)
        allow(artifacts).to receive(:runtime_metadata).and_return(
          instance_double(RuntimeMetadata::Schema, schema_artifact_extensions: {"example" => registration})
        )

        expect(artifacts.extension_artifacts.fetch("example")).to eq [Dir.pwd, {}]
      end

      context "before any artifacts have been dumped", :in_temp_dir do
        let(:artifacts) { FromDisk.new(Dir.pwd) }

        it "raises an error when accessing missing artifacts is attempted" do
          expect { artifacts.graphql_schema_string }.to raise_missing_artifacts_error
          expect { artifacts.indices }.to raise_missing_artifacts_error
          expect { artifacts.datastore_scripts }.to raise_missing_artifacts_error
          expect { artifacts.runtime_metadata }.to raise_missing_artifacts_error
        end

        def raise_missing_artifacts_error
          raise_error Errors::MissingSchemaArtifactError, a_string_including("could not be found", artifacts.artifacts_dir)
        end
      end

      describe "#index_mappings_by_index_def_name" do
        let(:artifacts) { FromDisk.new(::File.join(CommonSpecHelpers::REPO_ROOT, "config", "schema", "artifacts")) }

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
