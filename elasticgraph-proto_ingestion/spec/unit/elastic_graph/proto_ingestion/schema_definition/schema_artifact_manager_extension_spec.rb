# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/proto_ingestion/schema_definition/schema_artifact_manager_extension"
require "stringio"

module ElasticGraph
  module ProtoIngestion
    module SchemaDefinition
      RSpec.describe SchemaArtifactManagerExtension, :in_temp_dir do
        it "dumps the proto schema artifact alongside the base artifacts" do
          artifact_base_names = artifacts_for(define_indexed_type_schema)

          expect(artifact_base_names).to include(PROTO_SCHEMA_FILE)
        end

        it "omits the proto schema artifact when the schema defines no indexed types" do
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

          expect(artifact_base_names).not_to include(PROTO_SCHEMA_FILE)
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
