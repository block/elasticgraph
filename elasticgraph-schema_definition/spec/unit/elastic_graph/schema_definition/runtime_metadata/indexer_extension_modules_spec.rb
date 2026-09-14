# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require_relative "runtime_metadata_support"

module ElasticGraph
  module SchemaDefinition
    RSpec.describe "RuntimeMetadata #indexer_extension_modules" do
      include_context "RuntimeMetadata support"

      it "includes any modules registered during schema definition" do
        test_support_path = File.expand_path("../../../../../lib/elastic_graph/schema_definition/test_support.rb", __dir__)
        metadata = define_schema(extension_modules: []) do |s|
          s.register_indexer_extension TestSupport::IndexerExtension,
            defined_at: test_support_path
          s.register_indexer_extension Enumerable, defined_at: "set"

          s.object_type "Widget" do |t|
            t.field "id", "ID!"
            t.index "widgets"
          end
        end.runtime_metadata

        expect(metadata.indexer_extension_modules).to eq [
          SchemaArtifacts::RuntimeMetadata::ComponentExtension.new(
            SchemaArtifacts::RuntimeMetadata::Extension.new(
              TestSupport::IndexerExtension,
              test_support_path,
              {}
            ).to_dumpable_hash
          ),
          SchemaArtifacts::RuntimeMetadata::ComponentExtension.new(
            SchemaArtifacts::RuntimeMetadata::Extension.new(Enumerable, "set", {}).to_dumpable_hash
          )
        ]
      end

      it "rejects indexed schemas that have no registered indexer extension" do
        expect {
          define_schema(extension_modules: []) do |s|
            s.object_type "Widget" do |t|
              t.field "id", "ID!"
              t.index "widgets"
            end
          end.runtime_metadata
        }.to raise_error Errors::SchemaError, a_string_including(
          "defines indexed types but does not register an indexer extension",
          "Add an ingestion format extension"
        )
      end

      it "rejects indexed schemas whose indexer extensions do not provide ingestion adapters" do
        expect {
          define_schema(extension_modules: []) do |s|
            s.register_indexer_extension Enumerable, defined_at: "set"

            s.object_type "Widget" do |t|
              t.field "id", "ID!"
              t.index "widgets"
            end
          end.runtime_metadata
        }.to raise_error Errors::SchemaError, a_string_including("provides `ingestion_adapters_by_format`")
      end

      it "allows schemas with no indexed types to omit an indexer extension" do
        expect {
          define_schema(extension_modules: []) do |s|
            s.object_type "Widget" do |t|
              t.field "id", "ID!"
            end
          end.runtime_metadata
        }.not_to raise_error
      end
    end
  end
end
