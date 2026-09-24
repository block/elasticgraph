# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/errors"
require "elastic_graph/schema_artifacts/extension_artifacts"
require "elastic_graph/schema_artifacts/runtime_metadata/component_extension"

module ElasticGraph
  module SchemaArtifacts
    RSpec.describe ExtensionArtifacts do
      let(:registry) do
        registration = RuntimeMetadata::ComponentExtension.new(extension_ref: {
          "name" => "ElasticGraph::Extensions::ArtifactFactory",
          "require_path" => "support/example_extensions/artifact_factory",
          "config" => {"label" => "example"}
        })

        ExtensionArtifacts.new({"example" => registration}) do |factory, config|
          factory.from_disk("schema/artifacts", config: config)
        end
      end

      it "loads a registered provider with its configuration and caches it" do
        expect(registry.key?("example")).to be true
        provider = registry.fetch("example")

        expect(provider).to eq ["schema/artifacts", {label: "example"}]
        expect(registry.fetch("example")).to be(provider)
      end

      it "supports in-memory providers through the same registry" do
        registration = RuntimeMetadata::ComponentExtension.new(extension_ref: {
          "name" => "ElasticGraph::Extensions::ArtifactFactory",
          "require_path" => "support/example_extensions/artifact_factory"
        })
        results = Object.new
        in_memory_registry = ExtensionArtifacts.new({"example" => registration}) do |factory, config|
          factory.from_schema_definition(results, config: config)
        end

        expect(in_memory_registry.fetch("example")).to eq [results, {}]
      end

      it "reports an unregistered provider with an actionable error" do
        expect(registry.key?("missing")).to be false

        expect {
          registry.fetch("missing")
        }.to raise_error Errors::MissingSchemaArtifactError, a_string_including("missing", "regenerate the schema artifacts")
      end
    end
  end
end
