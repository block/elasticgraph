# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

RSpec.describe "elasticgraph-warehouse integration", :unit do
  include ElasticGraph::SchemaDefinition::TestSupport

  it "adds data_warehouse.yaml artifact via SchemaArtifactManager and generates config for simple scalar fields" do
    require "elastic_graph/warehouse/schema_definition/api_extension"

    results = define_schema(schema_element_name_form: :snake_case, extension_modules: [ElasticGraph::Warehouse::SchemaDefinition::APIExtension]) do |s|
      s.json_schema_version 1
      s.object_type "Person" do |t|
        t.field "id", "ID"
        t.field "name", "String"
        t.warehouse_table "person"
      end
    end

    expect(results.warehouse_config).to be_a(Hash)
    expect(results.warehouse_config.keys).to include("person")
    table = results.warehouse_config.fetch("person")

    expect(table.fetch("table_schema")).to include("id STRING", "name STRING")

    # Validate that SchemaArtifactManager will include the data_warehouse.yaml artifact
    Dir.mktmpdir do |tmp|
      out = StringIO.new
      mgr = ElasticGraph::SchemaDefinition::SchemaArtifactManager.new(
        schema_definition_results: results,
        schema_artifacts_directory: tmp,
        enforce_json_schema_version: false,
        output: out
      )

      mgr.dump_artifacts
      expect(File).to exist(File.join(tmp, "data_warehouse.yaml"))
      yaml = YAML.safe_load_file(File.join(tmp, "data_warehouse.yaml"))
      expect(yaml).to include("person")
    end
  end

  it "supports nested objects and lists with appropriate SQL mapping" do
    require "elastic_graph/warehouse/schema_definition/api_extension"

    results = define_schema(schema_element_name_form: :snake_case, extension_modules: [ElasticGraph::Warehouse::SchemaDefinition::APIExtension]) do |s|
      s.json_schema_version 1
      s.object_type "Employer" do |t|
        t.field "name", "String"
      end

      s.object_type "Person" do |t|
        t.field "name", "String"
        t.field "employer", "Employer"
        t.field "hobbies", "[String]"
        t.warehouse_table "person"
      end
    end

    table = results.warehouse_config.fetch("person")
    expect(table.fetch("table_schema")).to include(
      "name STRING",
      "employer STRUCT<name STRING>",
      "hobbies ARRAY<STRING>"
    )
  end

  it "allows overriding table type via scalar.warehouse_table options" do
    require "elastic_graph/warehouse/schema_definition/api_extension"

    results = define_schema(schema_element_name_form: :snake_case, extension_modules: [ElasticGraph::Warehouse::SchemaDefinition::APIExtension]) do |s|
      s.json_schema_version 1

      s.scalar_type "URL" do |t|
        t.mapping type: "keyword"
        t.json_schema type: "string", format: "uri"
        t.warehouse_table table_type: "STRING" # table schema type
      end

      s.object_type "Page" do |t|
        t.field "url", "URL"
        t.warehouse_table "page"
      end
    end

    table = results.warehouse_config.fetch("page")
    expect(table.fetch("table_schema")).to include("url STRING")
  end
end
