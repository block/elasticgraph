# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/constants"
require "elastic_graph/schema_definition/rake_tasks"
require "elastic_graph/warehouse/schema_definition/api_extension"
require "yaml"

module ElasticGraph
  module Warehouse
    module SchemaDefinition
      RSpec.describe "Warehouse RakeTasks", :rake_task, :in_temp_dir do
        describe "schema_artifacts:dump" do
          it "dumps warehouse artifact when warehouse tables are defined" do
            write_warehouse_schema(table_defs: <<~EOS)
              s.object_type "Product" do |t|
                t.field "id", "ID"
                t.field "name", "String"
                t.field "price", "Float"
                t.warehouse_table "products"
              end
            EOS

            expect {
              output = run_rake_with_warehouse("schema_artifacts:dump")
              expect(output.lines).to include(
                a_string_including("Dumped", Warehouse::DATA_WAREHOUSE_FILE)
              )
            }.to change { read_artifact(Warehouse::DATA_WAREHOUSE_FILE) }
              .from(a_falsy_value)
              .to(a_string_including("products:", "table_schema:", "CREATE TABLE IF NOT EXISTS products"))

            warehouse_config = YAML.safe_load(read_artifact(Warehouse::DATA_WAREHOUSE_FILE))
            expect(warehouse_config.keys).to eq(["tables"])
            expect(warehouse_config["tables"].keys).to eq(["products"])
            expect(warehouse_config["tables"]["products"]).to have_key("table_schema")
            expect(warehouse_config["tables"]["products"]["table_schema"]).to start_with("CREATE TABLE IF NOT EXISTS products")
          end

          it "does not dump warehouse artifact when no warehouse tables are defined" do
            write_warehouse_schema(table_defs: <<~EOS)
              s.object_type "User" do |t|
                t.field "id", "ID"
                t.field "name", "String"
                # No warehouse_table definition
              end
            EOS

            output = run_rake_with_warehouse("schema_artifacts:dump")

            expect(output.lines).not_to include(
              a_string_including("Dumped", Warehouse::DATA_WAREHOUSE_FILE)
            )
            expect(read_artifact(Warehouse::DATA_WAREHOUSE_FILE)).to be_falsy
          end

          it "idempotently dumps warehouse artifacts" do
            write_warehouse_schema(table_defs: <<~EOS)
              s.object_type "Product" do |t|
                t.field "id", "ID"
                t.warehouse_table "products"
              end
            EOS

            run_rake_with_warehouse("schema_artifacts:dump")

            expect {
              output = run_rake_with_warehouse("schema_artifacts:dump")
              expect(output.lines).to include(a_string_including("already up to date", Warehouse::DATA_WAREHOUSE_FILE))
            }.to maintain { read_artifact(Warehouse::DATA_WAREHOUSE_FILE) }
          end

          it "updates warehouse artifact when schema changes" do
            write_warehouse_schema(table_defs: <<~EOS)
              s.object_type "Product" do |t|
                t.field "id", "ID"
                t.warehouse_table "products"
              end
            EOS

            run_rake_with_warehouse("schema_artifacts:dump")
            original_content = read_artifact(Warehouse::DATA_WAREHOUSE_FILE)

            write_warehouse_schema(table_defs: <<~EOS)
              s.object_type "Product" do |t|
                t.field "id", "ID"
                t.field "name", "String"
                t.warehouse_table "products"
              end
            EOS

            expect {
              run_rake_with_warehouse("schema_artifacts:dump", enforce_json_schema_version: false)
            }.to change { read_artifact(Warehouse::DATA_WAREHOUSE_FILE) }
              .from(original_content)
              .to(a_string_including("products:", "name"))
          end

          it "sorts warehouse tables alphabetically by name" do
            write_warehouse_schema(table_defs: <<~EOS)
              s.object_type "Zebra" do |t|
                t.field "id", "ID"
                t.warehouse_table "zebras"
              end

              s.object_type "Apple" do |t|
                t.field "id", "ID"
                t.warehouse_table "apples"
              end

              s.object_type "Middle" do |t|
                t.field "id", "ID"
                t.warehouse_table "middles"
              end
            EOS

            run_rake_with_warehouse("schema_artifacts:dump")

            warehouse_config = YAML.safe_load(read_artifact(Warehouse::DATA_WAREHOUSE_FILE))
            expect(warehouse_config["tables"].keys).to eq(%w[apples middles zebras])
          end

          it "includes all warehouse table configurations" do
            write_warehouse_schema(table_defs: <<~EOS)
              s.object_type "Product" do |t|
                t.field "id", "ID"
                t.field "name", "String"
                t.field "price", "Float"
                t.warehouse_table "products"
              end

              s.object_type "User" do |t|
                t.field "user_id", "ID"
                t.field "email", "String"
                t.warehouse_table "users"
              end

              s.object_type "Order" do |t|
                t.field "order_id", "ID"
                t.warehouse_table "orders"
              end
            EOS

            run_rake_with_warehouse("schema_artifacts:dump")

            warehouse_config = YAML.safe_load(read_artifact(Warehouse::DATA_WAREHOUSE_FILE))
            expect(warehouse_config["tables"].keys).to contain_exactly("orders", "products", "users")

            warehouse_config["tables"].each do |table_name, table_config|
              expect(table_config).to have_key("table_schema")
              expect(table_config["table_schema"]).to start_with("CREATE TABLE IF NOT EXISTS #{table_name}")
            end
          end
        end

        def write_warehouse_schema(table_defs:)
          ::File.write("schema.rb", <<~EOS)
            ElasticGraph.define_schema do |s|
              s.json_schema_version 1

              # Add a dummy indexed type to ensure the Query type has at least one field.
              # This prevents GraphQL-Ruby warnings about empty Query types in tests.
              s.object_type "_DummyWarehouseTestType" do |t|
                t.field "id", "ID"
                t.index "dummy_warehouse_test_indices"
              end

              #{table_defs}
            end
          EOS
        end

        def run_rake_with_warehouse(*args, enforce_json_schema_version: true)
          run_rake(*args) do |output|
            ElasticGraph::SchemaDefinition::RakeTasks.new(
              schema_element_name_form: :snake_case,
              index_document_sizes: false,
              path_to_schema: "schema.rb",
              schema_artifacts_directory: "config/schema/artifacts",
              enforce_json_schema_version: enforce_json_schema_version,
              extension_modules: [Warehouse::SchemaDefinition::APIExtension],
              output: output
            )
          end
        end

        def read_artifact(name)
          path = File.join("config", "schema", "artifacts", name)
          File.exist?(path) && File.read(path)
        end
      end
    end
  end
end
