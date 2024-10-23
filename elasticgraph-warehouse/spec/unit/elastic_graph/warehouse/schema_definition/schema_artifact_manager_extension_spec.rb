# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/warehouse/schema_definition/api_extension"
require "tmpdir"

module ElasticGraph
  module Warehouse
    module SchemaDefinition
      RSpec.describe SchemaArtifactManagerExtension, :warehouse_schema do
        it "adds warehouse artifact when warehouse tables are defined" do
          results = define_warehouse_schema do |s|
            s.object_type "Product" do |t|
              t.field "id", "ID"
              t.field "name", "String"
              t.warehouse_table "products"
            end
          end

          Dir.mktmpdir do |tmp_dir|
            manager = results.state.factory.new_schema_artifact_manager(
              schema_definition_results: results,
              schema_artifacts_directory: tmp_dir,
              enforce_json_schema_version: false,
              output: StringIO.new
            )

            artifacts = manager.instance_variable_get(:@artifacts)
            warehouse_artifact = artifacts.find { |a| a.file_name.end_with?(Warehouse::DATA_WAREHOUSE_FILE) }

            expect(warehouse_artifact).not_to be_nil
            expect(warehouse_artifact.file_name).to eq(File.join(tmp_dir, Warehouse::DATA_WAREHOUSE_FILE))
          end
        end

        it "does not add warehouse artifact when no warehouse tables are defined" do
          results = define_warehouse_schema do |s|
            s.object_type "User" do |t|
              t.field "id", "ID"
              t.field "name", "String"
              # No warehouse_table definition
            end
          end

          Dir.mktmpdir do |tmp_dir|
            manager = results.state.factory.new_schema_artifact_manager(
              schema_definition_results: results,
              schema_artifacts_directory: tmp_dir,
              enforce_json_schema_version: false,
              output: StringIO.new
            )

            artifacts = manager.instance_variable_get(:@artifacts)
            warehouse_artifact = artifacts.find { |a| a.file_name.end_with?(Warehouse::DATA_WAREHOUSE_FILE) }

            expect(warehouse_artifact).to be_nil
          end
        end

        it "writes warehouse artifact to disk with correct structure" do
          results = define_warehouse_schema do |s|
            s.object_type "Product" do |t|
              t.field "id", "ID"
              t.field "name", "String"
              t.field "price", "Float"
              t.warehouse_table "products"
            end

            s.object_type "Order" do |t|
              t.field "order_id", "ID"
              t.field "total", "Float"
              t.warehouse_table "orders"
            end
          end

          Dir.mktmpdir do |tmp_dir|
            manager = results.state.factory.new_schema_artifact_manager(
              schema_definition_results: results,
              schema_artifacts_directory: tmp_dir,
              enforce_json_schema_version: false,
              output: StringIO.new
            )

            manager.dump_artifacts

            warehouse_file = File.join(tmp_dir, Warehouse::DATA_WAREHOUSE_FILE)
            expect(File.exist?(warehouse_file)).to be true

            content = YAML.safe_load(File.read(warehouse_file), permitted_classes: [Symbol])
            expect(content).to be_a(Hash)
            expect(content.keys).to contain_exactly("orders", "products")
            expect(content["products"]).to have_key("table_schema")
            expect(content["orders"]).to have_key("table_schema")
          end
        end

        it "sorts artifacts alphabetically by file name including warehouse artifact" do
          results = define_warehouse_schema do |s|
            s.object_type "Product" do |t|
              t.field "id", "ID"
              t.warehouse_table "products"
            end
          end

          Dir.mktmpdir do |tmp_dir|
            manager = results.state.factory.new_schema_artifact_manager(
              schema_definition_results: results,
              schema_artifacts_directory: tmp_dir,
              enforce_json_schema_version: false,
              output: StringIO.new
            )

            artifacts = manager.instance_variable_get(:@artifacts)
            file_names = artifacts.map(&:file_name)

            # Verify artifacts are sorted
            expect(file_names).to eq(file_names.sort)

            # Verify warehouse artifact is included in sorted list
            warehouse_file_name = File.join(tmp_dir, Warehouse::DATA_WAREHOUSE_FILE)
            expect(file_names).to include(warehouse_file_name)
          end
        end
      end
    end
  end
end
