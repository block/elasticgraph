# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

RSpec.describe ElasticGraph::Warehouse::Patches, :unit do
  include ElasticGraph::SchemaDefinition::TestSupport

  describe "Results patch" do
    it "adds warehouse_config method to Results" do
      require "elastic_graph/warehouse/schema_definition/api_extension"

      results = define_schema(schema_element_name_form: :snake_case, extension_modules: [ElasticGraph::Warehouse::SchemaDefinition::APIExtension]) do |s|
        s.json_schema_version 1

        s.object_type "Item" do |t|
          t.field "id", "ID"
          t.warehouse_table "items"
        end
      end

      expect(results).to respond_to(:warehouse_config)
      expect(results.warehouse_config).to be_a(Hash)
      expect(results.warehouse_config).to have_key("items")
    end

    it "returns empty hash when no warehouse tables are defined" do
      require "elastic_graph/warehouse/schema_definition/api_extension"

      results = define_schema(schema_element_name_form: :snake_case, extension_modules: [ElasticGraph::Warehouse::SchemaDefinition::APIExtension]) do |s|
        s.json_schema_version 1

        s.object_type "NoWarehouse" do |t|
          t.field "id", "ID"
        end
      end

      expect(results.warehouse_config).to eq({})
    end

    it "filters out types without warehouse_table_def" do
      require "elastic_graph/warehouse/schema_definition/api_extension"

      results = define_schema(schema_element_name_form: :snake_case, extension_modules: [ElasticGraph::Warehouse::SchemaDefinition::APIExtension]) do |s|
        s.json_schema_version 1

        # Union types don't have warehouse_table_def
        s.union_type "SearchResult" do |t|
          t.subtypes "Product", "Category"
        end

        s.object_type "Product" do |t|
          t.field "id", "ID"
          t.warehouse_table "products"
        end

        s.object_type "Category" do |t|
          t.field "id", "ID"
        end
      end

      expect(results.warehouse_config.keys).to eq(["products"])
    end
  end

  describe "SchemaArtifactManager patch" do
    it "adds warehouse artifact when warehouse tables are defined" do
      require "elastic_graph/warehouse/schema_definition/api_extension"
      require "tmpdir"

      Dir.mktmpdir do |dir|
        results = define_schema(schema_element_name_form: :snake_case, extension_modules: [ElasticGraph::Warehouse::SchemaDefinition::APIExtension]) do |s|
          s.json_schema_version 1

          s.object_type "User" do |t|
            t.field "id", "ID"
            t.warehouse_table "users"
          end
        end

        manager = ElasticGraph::SchemaDefinition::SchemaArtifactManager.new(
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
      require "elastic_graph/warehouse/schema_definition/api_extension"
      require "tmpdir"

      Dir.mktmpdir do |dir|
        results = define_schema(schema_element_name_form: :snake_case, extension_modules: [ElasticGraph::Warehouse::SchemaDefinition::APIExtension]) do |s|
          s.json_schema_version 1

          s.object_type "NoWarehouse" do |t|
            t.field "id", "ID"
          end
        end

        manager = ElasticGraph::SchemaDefinition::SchemaArtifactManager.new(
          schema_definition_results: results,
          schema_artifacts_directory: dir,
          enforce_json_schema_version: true,
          output: StringIO.new
        )

        warehouse_artifact = manager.instance_variable_get(:@artifacts).find { |a| a.file_name.include?("data_warehouse.yaml") }
        expect(warehouse_artifact).to be_nil
      end
    end

    it "handles errors gracefully and logs warning" do
      require "elastic_graph/warehouse/schema_definition/api_extension"
      require "tmpdir"

      Dir.mktmpdir do |dir|
        results = define_schema(schema_element_name_form: :snake_case, extension_modules: [ElasticGraph::Warehouse::SchemaDefinition::APIExtension]) do |s|
          s.json_schema_version 1

          s.object_type "Test" do |t|
            t.field "id", "ID"
            t.warehouse_table "test"
          end
        end

        # Mock warehouse_config to raise an error
        allow(results).to receive(:warehouse_config).and_raise(StandardError, "Test error")

        output = StringIO.new
        manager = ElasticGraph::SchemaDefinition::SchemaArtifactManager.new(
          schema_definition_results: results,
          schema_artifacts_directory: dir,
          enforce_json_schema_version: true,
          output: output
        )

        # Should not have warehouse artifact
        warehouse_artifact = manager.instance_variable_get(:@artifacts).find { |a| a.file_name.include?("data_warehouse.yaml") }
        expect(warehouse_artifact).to be_nil

        # Should have logged warning
        expect(output.string).to include("WARNING: Failed to generate warehouse config: Test error")
      end
    end

    it "handles nil output gracefully" do
      require "elastic_graph/warehouse/schema_definition/api_extension"
      require "tmpdir"

      Dir.mktmpdir do |dir|
        results = define_schema(schema_element_name_form: :snake_case, extension_modules: [ElasticGraph::Warehouse::SchemaDefinition::APIExtension]) do |s|
          s.json_schema_version 1

          s.object_type "Test" do |t|
            t.field "id", "ID"
            t.warehouse_table "test"
          end
        end

        # Mock warehouse_config to raise an error
        allow(results).to receive(:warehouse_config).and_raise(StandardError, "Test error")

        # Pass nil output - should not raise error
        expect {
          ElasticGraph::SchemaDefinition::SchemaArtifactManager.new(
            schema_definition_results: results,
            schema_artifacts_directory: dir,
            enforce_json_schema_version: true,
            output: nil
          )
        }.not_to raise_error
      end
    end
  end

  it "handles interface types in generate_warehouse_config" do
    require "elastic_graph/warehouse/schema_definition/api_extension"

    results = define_schema(schema_element_name_form: :snake_case, extension_modules: [ElasticGraph::Warehouse::SchemaDefinition::APIExtension]) do |s|
      s.json_schema_version 1

      # Interface types should be included if they have warehouse_table_def
      s.interface_type "TestInterface" do |t|
        t.field "id", "ID"
        t.warehouse_table "test_interfaces"
      end

      s.object_type "TestImpl" do |t|
        t.implements "TestInterface"
        t.field "id", "ID"
      end
    end

    expect(results.warehouse_config).to have_key("test_interfaces")
  end
end
