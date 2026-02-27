# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/constants"
require "elastic_graph/proto"
require "elastic_graph/proto/schema_definition/api_extension"
require "elastic_graph/schema_definition/rake_tasks"
require "fileutils"
require "yaml"

module ElasticGraph
  module Proto
    module SchemaDefinition
      RSpec.describe "Proto RakeTasks", :rake_task, :in_temp_dir do
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

          it "can replace json schema artifacts when proto replacement is configured" do
            write_proto_schema(
              proto_config: "s.proto_schema_artifacts replace_json_schemas: true",
              table_defs: <<~EOS
                s.object_type "Product" do |t|
                  t.field "id", "ID"
                  t.index "products"
                end
              EOS
            )

            run_rake_with_proto("schema_artifacts:dump", enforce_json_schema_version: false)

            expect(read_artifact(PROTO_SCHEMA_FILE)).to include('syntax = "proto3";')
            expect(read_artifact(DATASTORE_CONFIG_FILE)).not_to be_nil
            expect(read_artifact(RUNTIME_METADATA_FILE)).not_to be_nil
            expect(read_artifact(GRAPHQL_SCHEMA_FILE)).not_to be_nil
            expect(read_artifact(JSON_SCHEMAS_FILE)).to be_nil
            expect(read_versioned_json_schemas).to eq([])
          end

          it "does not enforce json schema version bumps when proto replaces json schema artifacts" do
            proto_config = "s.proto_schema_artifacts replace_json_schemas: true"

            write_proto_schema(
              proto_config: proto_config,
              table_defs: <<~EOS
                s.object_type "Product" do |t|
                  t.field "id", "ID"
                  t.index "products"
                end
              EOS
            )

            run_rake_with_proto("schema_artifacts:dump", enforce_json_schema_version: false)

            write_proto_schema(
              proto_config: proto_config,
              table_defs: <<~EOS
                s.object_type "Product" do |t|
                  t.field "id", "ID"
                  t.field "name", "String"
                  t.index "products"
                end
              EOS
            )

            expect {
              run_rake_with_proto("schema_artifacts:dump", enforce_json_schema_version: true)
            }.not_to raise_error

            expect(read_artifact(PROTO_SCHEMA_FILE)).to include("string name = 2;")
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
            write_proto_schema(
              proto_config: 's.proto_schema_artifacts field_number_mapping_file: "proto_field_numbers.yaml"',
              table_defs: <<~EOS
                s.object_type "Product" do |t|
                  t.field "id", "ID"
                  t.field "name", "String"
                  t.index "products"
                end
              EOS
            )

            run_rake_with_proto("schema_artifacts:dump", enforce_json_schema_version: false)

            expect(read_artifact(PROTO_FIELD_NUMBERS_FILE)).not_to be_nil
            expect(parsed_proto_field_numbers).to eq({
              "messages" => {
                "Product" => {
                  "id" => 1,
                  "name" => 2
                }
              }
            })

            write_proto_schema(
              proto_config: 's.proto_schema_artifacts field_number_mapping_file: "proto_field_numbers.yaml"',
              table_defs: <<~EOS
                s.object_type "Product" do |t|
                  t.field "name", "String"
                  t.field "id", "ID"
                  t.index "products"
                end
              EOS
            )

            run_rake_with_proto("schema_artifacts:dump", enforce_json_schema_version: false)

            expect(read_artifact(PROTO_SCHEMA_FILE)).to include("string name = 2;")
            expect(read_artifact(PROTO_SCHEMA_FILE)).to include("string id = 1;")
          end

          it "supports absolute field-number mapping paths and treats empty yaml as empty mappings" do
            mapping_file = ::File.expand_path("config/schema/artifacts/absolute_proto_field_numbers.yaml")
            ::FileUtils.mkdir_p(::File.dirname(mapping_file))
            ::File.write(mapping_file, "")

            write_proto_schema(
              proto_config: "s.proto_schema_artifacts field_number_mapping_file: #{mapping_file.inspect}",
              table_defs: <<~EOS
                s.object_type "Product" do |t|
                  t.field "id", "ID"
                  t.field "name", "String"
                  t.index "products"
                end
              EOS
            )

            run_rake_with_proto("schema_artifacts:dump", enforce_json_schema_version: false)

            expect(read_artifact(PROTO_SCHEMA_FILE)).to include("string id = 1;")
            expect(read_artifact(PROTO_SCHEMA_FILE)).to include("string name = 2;")
          end

          it "fails when field-number mapping is enforced but mapping file is missing" do
            write_proto_schema(
              proto_config: 's.proto_schema_artifacts field_number_mapping_file: "proto_field_numbers.yaml", enforce_field_number_mapping: true',
              table_defs: <<~EOS
                s.object_type "Product" do |t|
                  t.field "id", "ID"
                  t.field "name", "String"
                  t.index "products"
                end
              EOS
            )

            expect {
              run_rake_with_proto("schema_artifacts:dump")
            }.to raise_error(ElasticGraph::Errors::SchemaError, a_string_including("does not exist"))
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

        def read_versioned_json_schemas
          Dir.glob(File.join("config", "schema", "artifacts", JSON_SCHEMAS_BY_VERSION_DIRECTORY, "*.yaml"))
        end

        def parsed_proto_field_numbers
          ::YAML.safe_load(read_artifact(PROTO_FIELD_NUMBERS_FILE))
        end
      end
    end
  end
end
