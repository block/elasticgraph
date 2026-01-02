# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/errors"
require "elastic_graph/schema_artifacts"

module ElasticGraph
  module SchemaArtifacts
    RSpec.describe SchemaArtifacts do
      describe ".from_yaml_file" do
        it "uses the `schema_artifacts.directory` setting in the YAML file to build a `FromDisk` instance" do
          artifacts = SchemaArtifacts.from_yaml_file(CommonSpecHelpers.test_settings_file)

          expect(artifacts).to be_a(FromDisk)
          expect(artifacts.artifacts_dir).to eq "config/schema/artifacts"
        end
      end

      describe ".from_parsed_yaml" do
        it "uses the `schema_artifacts.directory` setting to build a `FromDisk` instance" do
          artifacts = from_parsed_yaml({"schema_artifacts" => {"directory" => "some_dir"}})

          expect(artifacts).to be_a(FromDisk)
          expect(artifacts.artifacts_dir).to eq "some_dir"
        end

        it "uses a sensible directory by default when `schema_artifacts` is not configured" do
          artifacts = from_parsed_yaml({})

          expect(artifacts).to be_a(FromDisk)
          expect(artifacts.artifacts_dir).to eq "config/schema/artifacts"
        end

        it "fails with a clear error if extra `schema_artifacts` settings are provided" do
          expect {
            from_parsed_yaml({"schema_artifacts" => {"directory" => "a", "foo" => 3}})
          }.to raise_error Errors::ConfigError, a_string_including("foo")
        end

        def from_parsed_yaml(parsed_yaml)
          SchemaArtifacts.from_parsed_yaml(parsed_yaml)
        end
      end
    end
  end
end
