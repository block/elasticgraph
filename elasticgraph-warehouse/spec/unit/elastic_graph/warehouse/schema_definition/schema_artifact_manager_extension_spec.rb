# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/schema_definition/test_support"
require "elastic_graph/warehouse/schema_definition/api_extension"
require "tmpdir"

module ElasticGraph
  module Warehouse
    module SchemaDefinition
      RSpec.describe SchemaArtifactManagerExtension, :unit do
        include ElasticGraph::SchemaDefinition::TestSupport

        it "adds warehouse artifact when warehouse tables are defined" do
          Dir.mktmpdir do |dir|
            factory = nil
            results = define_schema(schema_element_name_form: :snake_case, extension_modules: [APIExtension]) do |s|
              factory = s.factory
              s.json_schema_version 1

              s.object_type "User" do |t|
                t.field "id", "ID"
                t.warehouse_table "users"
              end
            end

            manager = factory.new_schema_artifact_manager(
              schema_definition_results: results,
              schema_artifacts_directory: dir,
              enforce_json_schema_version: true,
              output: StringIO.new
            )

            warehouse_artifact = manager.instance_variable_get(:@artifacts).find { |a| a.file_name.include?("data_warehouse.yaml") }
            expect(warehouse_artifact).not_to be_nil
            expect(warehouse_artifact.desired_contents).to have_key("users")
          end
        end

        it "does not add warehouse artifact when no warehouse tables are defined" do
          Dir.mktmpdir do |dir|
            factory = nil
            results = define_schema(schema_element_name_form: :snake_case, extension_modules: [APIExtension]) do |s|
              factory = s.factory
              s.json_schema_version 1

              s.object_type "NoWarehouse" do |t|
                t.field "id", "ID"
              end
            end

            manager = factory.new_schema_artifact_manager(
              schema_definition_results: results,
              schema_artifacts_directory: dir,
              enforce_json_schema_version: true,
              output: StringIO.new
            )

            warehouse_artifact = manager.instance_variable_get(:@artifacts).find { |a| a.file_name.include?("data_warehouse.yaml") }
            expect(warehouse_artifact).to be_nil
          end
        end

        it "does not add warehouse artifact when schema definition results don't respond to warehouse_config" do
          Dir.mktmpdir do |dir|
            # Create a mock results object that doesn't respond to warehouse_config
            results = double("results", respond_to?: false)

            # Create a manager and manually extend it with the extension to test the guard clause
            manager = ElasticGraph::SchemaDefinition::SchemaArtifactManager.allocate
            manager.instance_variable_set(:@schema_definition_results, results)
            manager.instance_variable_set(:@schema_artifacts_directory, dir)
            manager.instance_variable_set(:@artifacts, [])
            manager.extend SchemaArtifactManagerExtension

            # Call add_warehouse_artifact - it should return early without adding an artifact
            manager.add_warehouse_artifact

            artifacts = manager.instance_variable_get(:@artifacts)
            expect(artifacts).to be_empty
          end
        end
      end
    end
  end
end
