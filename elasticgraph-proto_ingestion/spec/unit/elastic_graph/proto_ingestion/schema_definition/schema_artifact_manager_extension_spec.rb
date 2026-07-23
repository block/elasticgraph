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
        it "dumps proto artifacts alongside the base artifacts" do
          artifact_base_names = artifacts_for(define_indexed_type_schema)

          expect(artifact_base_names).to include(PROTO_SCHEMA_FILE, PROTO_FIELD_NUMBERS_FILE)
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

          artifact_base_names = artifacts_for(results)

          expect(artifact_base_names).not_to include(PROTO_SCHEMA_FILE, PROTO_FIELD_NUMBERS_FILE)
        end

        it "seeds proto generation with the field-number mappings from a previously dumped artifact" do
          ::FileUtils.mkdir_p("artifacts")
          ::File.write(::File.join("artifacts", PROTO_FIELD_NUMBERS_FILE), <<~YAML)
            messages:
              Widget:
                fields:
                  id: 7
          YAML

          results = define_indexed_type_schema
          artifacts_for(results)

          expect(results.proto_schema).to include("string id = 7;")
        end

        it "seeds proto generation with the enum value numbers from a previously dumped artifact" do
          ::FileUtils.mkdir_p("artifacts")
          ::File.write(::File.join("artifacts", PROTO_FIELD_NUMBERS_FILE), <<~YAML)
            enums:
              Status:
                values:
                  INACTIVE: 5
          YAML

          results = define_proto_schema_results do |s|
            s.enum_type "Status" do |t|
              t.values "ACTIVE", "INACTIVE"
            end

            s.object_type "Widget" do |t|
              t.field "id", "ID"
              t.field "status", "Status"
              t.index "widgets"
            end
          end
          artifacts_for(results)

          expect(results.proto_schema).to include("STATUS_ACTIVE = 1;", "STATUS_INACTIVE = 5;")
        end

        def define_indexed_type_schema
          define_proto_schema_results do |s|
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

          manager.send(:artifacts_from_schema_def).map { |artifact| ::File.basename(artifact.file_name) }
        end
      end
    end
  end
end
