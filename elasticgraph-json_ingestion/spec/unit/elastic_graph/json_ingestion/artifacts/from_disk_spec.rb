# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/json_ingestion/artifacts/from_disk"

module ElasticGraph
  module JSONIngestion
    module Artifacts
      RSpec.describe FromDisk do
        context "with multiple json schemas", :in_temp_dir do
          let(:artifacts) { FromDisk.new(Dir.pwd) }

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

        context "without JSON schemas", :in_temp_dir do
          let(:artifacts) { FromDisk.new(Dir.pwd) }
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
      end
    end
  end
end
