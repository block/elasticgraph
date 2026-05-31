# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/constants"
require "elastic_graph/json_ingestion/schema_definition/api_extension"
require "elastic_graph/schema_definition/rake_tasks"
require "fileutils"
require "yaml"

module ElasticGraph
  module JSONIngestion
    module SchemaDefinition
      RSpec.describe SchemaArtifactManagerExtension, :in_temp_dir, :rake_task do
        after do
          Thread.current[:eg_schema_load_count] = nil
        end

        it "dumps public JSON schemas and private versioned JSON schemas with ElasticGraph metadata" do
          write_schema(json_schema_version: 1)
          output = run_rake("schema_artifacts:dump")

          expect(output.lines).to include(
            a_string_including("Dumped", JSON_SCHEMAS_FILE),
            a_string_including("Dumped", versioned_json_schema_file(1))
          )

          public_id_schema = read_yaml_artifact(JSON_SCHEMAS_FILE).dig("$defs", "Widget", "properties", "id")
          versioned_id_schema = read_yaml_artifact(versioned_json_schema_file(1)).dig("$defs", "Widget", "properties", "id")

          expect(public_id_schema).to eq(json_schema_for_keyword_type("ID"))
          expect(versioned_id_schema).to eq(json_schema_for_keyword_type("ID", {
            "ElasticGraph" => {
              "type" => "ID!",
              "nameInIndex" => "id"
            }
          }))

          expect(run_rake("schema_artifacts:dump")).to include("is already up to date", JSON_SCHEMAS_FILE)
        end

        it "requires JSON schema version bumps unless enforcement is disabled" do
          write_schema(json_schema_version: 1)
          run_rake("schema_artifacts:dump")

          write_schema(json_schema_version: 2)
          expect {
            run_rake("schema_artifacts:dump")
          }.to change { read_artifact(JSON_SCHEMAS_FILE) }
            .from(a_string_including("\njson_schema_version: 1\n"))
            .to(a_string_including("\njson_schema_version: 2\n"))

          write_schema(json_schema_version: 2, extra_widget_body: "t.field 'color', 'String!'")
          expect {
            run_rake("schema_artifacts:dump")
          }.to abort_with a_string_including(
            "A change has been attempted to `json_schemas.yaml`",
            "`schema.json_schema_version 3`"
          ).and matching(/line \d+ at `(\S*\/?)schema\.rb`/)

          write_schema(
            json_schema_version: 2,
            extra_widget_body: "t.field 'color', 'String!'",
            enforce_json_schema_version: false
          )

          expect(run_rake("schema_artifacts:dump")).to include(
            "WARNING: the `json_schemas.yaml` artifact is being updated without the `json_schema_version` being correspondingly incremented"
          )
        end

        it "keeps field metadata up to date on every versioned JSON schema" do
          write_schema(json_schema_version: 1)
          run_rake("schema_artifacts:dump")

          write_schema(json_schema_version: 2, extra_widget_body: "t.field 'color', 'String!'")
          run_rake("schema_artifacts:dump")

          write_schema(
            json_schema_version: 2,
            name_field_suffix: ", name_in_index: 'name2'",
            extra_widget_body: "t.field 'color', 'String!'"
          )
          run_rake("schema_artifacts:dump")

          loaded_v1 = read_yaml_artifact(versioned_json_schema_file(1))
          loaded_v2 = read_yaml_artifact(versioned_json_schema_file(2))

          expect(loaded_v1.dig("$defs", "Widget", "properties", "name")).to eq(
            json_schema_for_keyword_type("String", {
              "ElasticGraph" => {
                "type" => "String!",
                "nameInIndex" => "name2"
              }
            })
          )
          expect(loaded_v1.dig("$defs", "Widget", "properties", "color")).to eq(nil)

          expect(loaded_v2.dig("$defs", "Widget", "properties", "name")).to eq(
            json_schema_for_keyword_type("String", {
              "ElasticGraph" => {
                "type" => "String!",
                "nameInIndex" => "name2"
              }
            })
          )
          expect(loaded_v2.dig("$defs", "Widget", "properties", "color")).to eq(
            json_schema_for_keyword_type("String", {
              "ElasticGraph" => {
                "type" => "String!",
                "nameInIndex" => "color"
              }
            })
          )
        end

        it "gives clear errors for old schema versions with missing fields or types" do
          write_schema(json_schema_version: 8)
          run_rake("schema_artifacts:dump")
          write_schema(json_schema_version: 9, omit_widget_name_field: true)
          expect { run_rake("schema_artifacts:dump") }.to abort_with a_string_including(
            "The `Widget.name` field (which existed in JSON schema version 8) no longer exists",
            "at this old version",
            "delete its file from `json_schemas_by_version`"
          )

          write_schema(json_schema_version: 9)
          run_rake("schema_artifacts:dump")
          write_schema(json_schema_version: 10, omit_widget_name_field: true)
          expect { run_rake("schema_artifacts:dump") }.to abort_with a_string_including(
            "The `Widget.name` field (which existed in JSON schema versions 8 and 9) no longer exists",
            "at these old versions",
            "delete their files from `json_schemas_by_version`"
          )

          write_schema(json_schema_version: 10)
          run_rake("schema_artifacts:dump")
          write_schema(json_schema_version: 11, omit_widget_name_field: true)
          expect { run_rake("schema_artifacts:dump") }.to abort_with a_string_including(
            "The `Widget.name` field (which existed in JSON schema versions 8, 9, and 10) no longer exists"
          )

          write_schema(json_schema_version: 11, omit_widget_name_field: true, extra_widget_body: "t.field('full_name', 'String') { |f| f.renamed_from 'name' }")
          run_rake("schema_artifacts:dump")

          delete_artifact(JSON_SCHEMAS_FILE)
          write_schema(json_schema_version: 11, omit_widget_name_field: true, extra_widget_body: "t.deleted_field 'name'")
          run_rake("schema_artifacts:dump")

          delete_artifacts
          write_schema(json_schema_version: 1)
          run_rake("schema_artifacts:dump")
          write_schema(json_schema_version: 2, widget_type_name: "Widget2")
          expect { run_rake("schema_artifacts:dump") }.to abort_with a_string_including(
            "The `Widget` type (which existed in JSON schema version 1) no longer exists",
            "If the `Widget` type has been renamed"
          )
        end

        it "reports deprecated schema element warnings, conflicts, and missing necessary fields" do
          ::File.write("schema.rb", <<~EOS)
            ElasticGraph.define_schema do |schema|
              schema.json_schema_version 1
              schema.deleted_type "SomeType"

              schema.object_type "Widget" do |t|
                t.renamed_from "OldWidget"
                t.deleted_field "old_name"
                t.field "id", "ID!"
                t.field "name", "String" do |f|
                  f.renamed_from "old_name"
                end
                t.index "widgets"
              end
            end
          EOS

          expect(run_rake("schema_artifacts:dump")).to include(
            "The schema definition has 4 unneeded reference(s)",
            "`schema.deleted_type \"SomeType\"`",
            "`type.renamed_from \"OldWidget\"`",
            "`type.deleted_field \"old_name\"`",
            "`field.renamed_from \"old_name\"`"
          )

          delete_artifacts
          ::File.write("schema.rb", <<~EOS)
            ElasticGraph.define_schema do |schema|
              schema.json_schema_version 1
              schema.deleted_type "Widget"

              schema.object_type "Widget" do |t|
                t.field "id", "ID!"
                t.index "widgets"

                t.field "token", "ID" do |f|
                  f.renamed_from "id"
                end
                t.deleted_field "id"
              end
            end
          EOS

          expect {
            run_rake("schema_artifacts:dump")
          }.to abort_with a_string_including(
            "The schema definition of `Widget` has conflicts",
            "The schema definition of `Widget.id` has conflicts"
          )

          delete_artifacts
          ::File.write("schema.rb", <<~EOS)
            ElasticGraph.define_schema do |schema|
              schema.json_schema_version 1

              schema.object_type "Embedded" do |t|
                t.field "workspace_id", "ID"
                t.field "created_at", "DateTime"
              end

              schema.object_type "Widget" do |t|
                t.field "id", "ID"
                t.field "embedded", "Embedded"
                t.index "widgets" do |i|
                  i.route_with "embedded.workspace_id"
                  i.rollover :yearly, "embedded.created_at"
                end
              end
            end
          EOS

          run_rake("schema_artifacts:dump")

          ::File.write("schema.rb", <<~EOS)
            ElasticGraph.define_schema do |schema|
              schema.json_schema_version 2

              schema.object_type "Embedded" do |t|
                t.field "workspace_id2", "ID", name_in_index: "workspace_id"
                t.deleted_field "workspace_id"

                t.field "created_at2", "DateTime", name_in_index: "created_at"
                t.deleted_field "created_at"
              end

              schema.object_type "Widget" do |t|
                t.field "id", "ID"
                t.field "embedded", "Embedded"
                t.index "widgets" do |i|
                  i.route_with "embedded.workspace_id2"
                  i.rollover :yearly, "embedded.created_at2"
                end
              end
            end
          EOS

          expect {
            run_rake("schema_artifacts:dump")
          }.to abort_with a_string_including(
            "JSON schema version 1 has no field that maps to the routing field path of `Widget.embedded.workspace_id`",
            "JSON schema version 1 has no field that maps to the rollover field path of `Widget.embedded.created_at`"
          )
        end

        def write_schema(
          json_schema_version:,
          enforce_json_schema_version: true,
          widget_type_name: "Widget",
          name_field_suffix: "",
          extra_widget_body: "",
          omit_widget_name_field: false
        )
          ::File.write("schema.rb", <<~EOS)
            Thread.current[:eg_schema_load_count] = (Thread.current[:eg_schema_load_count] || 0) + 1
            raise "Schema file was loaded more than once!" if Thread.current[:eg_schema_load_count] > 1

            ElasticGraph.define_schema do |schema|
              schema.json_schema_version #{json_schema_version}
              #{"schema.enforce_json_schema_version false" unless enforce_json_schema_version}

              schema.object_type "#{widget_type_name}" do |t|
                t.field "id", "ID!"
                #{%(t.field "name", "String!"#{name_field_suffix}) unless omit_widget_name_field}
                #{extra_widget_body}
                t.index "widgets"
              end
            end
          EOS
        end

        def run_rake(*args)
          Thread.current[:eg_schema_load_count] = nil

          super(*args) do |output|
            ::ElasticGraph::SchemaDefinition::RakeTasks.new(
              schema_element_name_form: :snake_case,
              index_document_sizes: true,
              path_to_schema: "schema.rb",
              schema_artifacts_directory: "config/schema/artifacts",
              extension_modules: [APIExtension],
              output: output
            )
          end
        end

        def read_artifact(*name_parts)
          path = ::File.join("config", "schema", "artifacts", *name_parts)
          ::File.exist?(path) && ::File.read(path)
        end

        def read_yaml_artifact(*name_parts)
          ::YAML.safe_load(read_artifact(*name_parts))
        end

        def delete_artifact(*name_parts)
          ::File.delete(::File.join("config", "schema", "artifacts", *name_parts))
        end

        def delete_artifacts
          ::FileUtils.rm_rf(::File.join("config", "schema", "artifacts"))
        end

        def versioned_json_schema_file(version)
          ::File.join(JSON_SCHEMAS_BY_VERSION_DIRECTORY, "v#{version}.yaml")
        end

        def json_schema_for_keyword_type(type, extras = {})
          {
            "allOf" => [
              {"$ref" => "#/$defs/#{type}"},
              {"maxLength" => DEFAULT_MAX_KEYWORD_LENGTH}
            ]
          }.merge(extras)
        end
      end
    end
  end
end
