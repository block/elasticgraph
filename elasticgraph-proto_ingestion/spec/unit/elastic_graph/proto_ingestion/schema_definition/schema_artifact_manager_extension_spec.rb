# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/proto_ingestion/schema_definition/schema_artifact_manager_extension"
require "fileutils"
require "stringio"

module ElasticGraph
  module ProtoIngestion
    module SchemaDefinition
      RSpec.describe SchemaArtifactManagerExtension, :in_temp_dir do
        it "locates `#{PROTO_FIELD_NUMBERS_FILE}` alongside the schema definition since it is an input to schema generation, unlike the proper schema artifacts" do
          artifacts_by_file_name = artifacts_for(define_indexed_type_schema).to_h do |artifact|
            [artifact.file_name, artifact]
          end

          expect(artifacts_by_file_name.keys).to include(
            ::File.join("config", PROTO_FIELD_NUMBERS_FILE),
            ::File.join("artifacts", PROTO_SCHEMA_FILE)
          )
        end

        it "documents the file's hand-editable input-file semantics instead of the standard `DO NOT EDIT BY HAND` preamble" do
          artifact = artifacts_for(define_indexed_type_schema).find do |candidate|
            ::File.basename(candidate.file_name) == PROTO_FIELD_NUMBERS_FILE
          end

          artifact.dump(::StringIO.new)
          contents = ::File.read(::File.join("config", PROTO_FIELD_NUMBERS_FILE))

          expect(contents).to start_with("# This file is part of your schema definition")
          expect(contents).to include("While prototyping, you may")
          expect(contents).to include("Once generated protos have been used")
          expect(contents).to include("you must NOT delete this file and regenerate it")
          expect(contents).not_to include("DO NOT EDIT BY HAND")
        end

        it "omits proto artifacts when the schema defines no indexed types" do
          results = define_proto_schema_results do |s|
            s.object_type "Point" do |t|
              t.field "x", "Float"
              t.field "y", "Float"
            end

            s.on_root_query_type do |t|
              # Avoid an "Object types must have fields" warning from the GraphQL gem.
              t.field "point", "Point" do |f|
                f.resolve_with :object_without_lookahead
              end
            end
          end

          artifact_base_names = artifact_base_names_for(results)

          expect(artifact_base_names).not_to include(PROTO_SCHEMA_FILE, PROTO_FIELD_NUMBERS_FILE)
        end

        it "seeds proto generation with previously dumped field and enum numbers before an artifact manager is constructed" do
          ::FileUtils.mkdir_p("config")
          ::File.write(::File.join("config", PROTO_FIELD_NUMBERS_FILE), <<~YAML)
            messages:
              Widget:
                fields:
                  id: 7
            enums:
              Status:
                values:
                  INACTIVE: 5
          YAML

          results = define_proto_schema_results(path_to_schema: ::File.join("config", "schema.rb")) do |s|
            s.enum_type "Status" do |t|
              t.values "ACTIVE", "INACTIVE"
            end

            s.object_type "Widget" do |t|
              t.field "id", "ID"
              t.field "status", "Status"
              t.index "widgets"
            end
          end

          expect(results.proto_schema).to include(
            "string id = 7;",
            "STATUS_ACTIVE = 1;",
            "STATUS_INACTIVE = 5;"
          )
        end

        it "raises a clear error when dumping proto artifacts without a configured `path_to_schema`" do
          results = define_proto_schema_results do |s|
            s.object_type "Widget" do |t|
              t.field "id", "ID"
              t.index "widgets"
            end
          end

          expect {
            artifacts_for(results)
          }.to raise_error Errors::SchemaError, a_string_including("without a configured `path_to_schema`")
        end

        def define_indexed_type_schema
          define_proto_schema_results(path_to_schema: ::File.join("config", "schema.rb")) do |s|
            s.object_type "Widget" do |t|
              t.field "id", "ID"
              t.index "widgets"
            end
          end
        end

        def artifacts_for(results)
          manager = results.state.api.factory.new_schema_artifact_manager(
            schema_definition_results: results,
            schema_artifacts_directory: "artifacts",
            output: ::StringIO.new
          )

          manager.send(:artifacts_from_schema_def)
        end

        def artifact_base_names_for(results)
          artifacts_for(results).map { |artifact| ::File.basename(artifact.file_name) }
        end
      end
    end
  end
end
