# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/proto_ingestion/artifacts"
require "elastic_graph/proto_ingestion/schema_definition/api_extension"
require "elastic_graph/schema_artifacts/from_disk"
require "elastic_graph/schema_definition/test_support"

module ElasticGraph
  module ProtoIngestion
    RSpec.describe Artifacts do
      it "exposes a generated protobuf schema through both provider implementations", :in_temp_dir do
        results = ElasticGraph::SchemaDefinition::TestSupport.define_schema(
          schema_element_name_form: :snake_case,
          path_to_schema: File.join(Dir.pwd, "schema.rb"),
          extension_modules: [ElasticGraph::SchemaDefinition::TestSupport::APIExtension, SchemaDefinition::APIExtension]
        ) do |schema|
          schema.object_type "Widget" do |type|
            type.field "id", "ID!"
            type.index "widgets"
          end
        end
        results.state.factory.new_schema_artifact_manager(
          schema_definition_results: results, schema_artifacts_directory: Dir.pwd, output: StringIO.new
        ).dump_artifacts

        generated = results.extension_artifacts.fetch("proto").proto_schema
        disk = SchemaArtifacts::FromDisk.new(Dir.pwd).extension_artifacts.fetch("proto")
        expect(generated).to include("message Widget")
        loaded = disk.proto_schema
        expect(loaded).to end_with(generated.chomp)
        expect(disk.proto_schema).to be loaded
      end

      it "reports a missing protobuf schema", :in_temp_dir do
        expect {
          Artifacts.from_disk(Dir.pwd, config: {}).proto_schema
        }.to raise_error Errors::MissingSchemaArtifactError, a_string_including("schema.proto", Dir.pwd)
      end

      it "reports a missing in-memory protobuf schema when no messages were generated" do
        results = ElasticGraph::SchemaDefinition::TestSupport.define_schema(
          schema_element_name_form: :snake_case, extension_modules: [SchemaDefinition::APIExtension]
        )

        expect {
          results.extension_artifacts.fetch("proto").proto_schema
        }.to raise_error Errors::MissingSchemaArtifactError, a_string_including("schema.proto", "no protobuf messages")
      end
    end
  end
end
