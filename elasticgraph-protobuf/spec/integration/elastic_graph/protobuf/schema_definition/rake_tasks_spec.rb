# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/constants"
require "elastic_graph/protobuf"
require "elastic_graph/protobuf/schema_definition/api_extension"
require "elastic_graph/schema_definition/rake_tasks"
require "fileutils"
require "yaml"

module ElasticGraph
  module Protobuf
    module SchemaDefinition
      RSpec.describe "Protobuf RakeTasks", :rake_task, :in_temp_dir do
        describe "schema_artifacts:dump" do
          it "dumps proto artifact when indexed types are defined" do
            write_proto_schema(table_defs: <<~EOS)
              s.object_type "Product" do |t|
                t.field "id", "ID"
                t.field "name", "String"
                t.index "products"
              end
            EOS

            expect {
              output = run_rake_with_proto("schema_artifacts:dump")
              expect(output.lines).to include(a_string_including("Dumped", PROTO_SCHEMA_FILE))
            }.to change { read_artifact(PROTO_SCHEMA_FILE) }
              .from(nil)
              .to(a_string_including('syntax = "proto3";', "message Product", "string name = 2;"))
          end

          it "idempotently dumps proto artifacts" do
            write_proto_schema(table_defs: <<~EOS)
              s.object_type "Product" do |t|
                t.field "id", "ID"
                t.index "products"
              end
            EOS

            run_rake_with_proto("schema_artifacts:dump", enforce_json_schema_version: false)

            expect {
              output = run_rake_with_proto("schema_artifacts:dump")
              expect(output.lines).to include(a_string_including("already up to date", PROTO_SCHEMA_FILE))
            }.to maintain { read_artifact(PROTO_SCHEMA_FILE) }
          end

          it "can persist and reuse proto field-number mappings from an artifact file" do
            write_proto_schema(table_defs: <<~EOS)
              s.object_type "Product" do |t|
                t.field "id", "ID"
                t.field "name", "String"
                t.index "products"
              end
            EOS

            run_rake_with_proto("schema_artifacts:dump", enforce_json_schema_version: false)

            expect(read_artifact(PROTO_FIELD_NUMBERS_FILE)).not_to be_nil
            expect(parsed_proto_field_numbers).to eq({
              "messages" => {
                "Product" => {
                  "fields" => {
                    "id" => 1,
                    "name" => 2
                  }
                }
              }
            })

            write_proto_schema(table_defs: <<~EOS)
              s.object_type "Product" do |t|
                t.field "name", "String"
                t.field "id", "ID"
                t.index "products"
              end
            EOS

            run_rake_with_proto("schema_artifacts:dump", enforce_json_schema_version: false)

            expect(read_artifact(PROTO_SCHEMA_FILE)).to include("string name = 2;")
            expect(read_artifact(PROTO_SCHEMA_FILE)).to include("string id = 1;")
          end
        end

        private

        def write_proto_schema(table_defs:, proto_config: nil)
          ::File.write("schema.rb", <<~EOS)
            ElasticGraph.define_schema do |s|
              s.json_schema_version 1
              #{proto_config}

              #{table_defs}
            end
          EOS
        end

        def run_rake_with_proto(*args, enforce_json_schema_version: true)
          run_rake(*args) do |output|
            ElasticGraph::SchemaDefinition::RakeTasks.new(
              schema_element_name_form: :snake_case,
              index_document_sizes: false,
              path_to_schema: "schema.rb",
              schema_artifacts_directory: "config/schema/artifacts",
              enforce_json_schema_version: enforce_json_schema_version,
              extension_modules: [SchemaDefinition::APIExtension],
              output: output
            )
          end
        end

        def read_artifact(name)
          path = File.join("config", "schema", "artifacts", name)
          File.read(path) if File.exist?(path)
        end

        def parsed_proto_field_numbers
          ::YAML.safe_load(read_artifact(PROTO_FIELD_NUMBERS_FILE))
        end
      end
    end
  end
end
