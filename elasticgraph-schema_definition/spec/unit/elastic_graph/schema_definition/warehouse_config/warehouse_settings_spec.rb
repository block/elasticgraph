# Copyright 2024 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/spec_support/schema_definition_helpers"

module ElasticGraph
  module SchemaDefinition
    RSpec.describe "warehouse support" do
      include_context "SchemaDefinitionHelpers"
      it "returns reasonable default settings that we want to use for a table" do

        config = define_schema(
          schema_element_name_form: "snake_case")  do |s|
          s.object_type "MyType" do |t|
            t.field "id", "ID"
            t.warehouse_table "my_type"
          end
        end



        expect(config.warehouse_config["my_type"]).to include(
          "create_table_command" => "CREATE TABLE IF NOT EXISTS my_type (id  STRING);",
          "parquet_definition" => "message my_type {\nid  binary;\n}\n",
        )
      end

      it "handles standard scalar and enum types" do
        config = define_schema(
          schema_element_name_form: "snake_case")  do |s|
          s.enum_type "Color" do |t|
            t.values "RED", "GREEN", "YELLOW"
          end

          s.object_type "MyType" do |t|
            t.field "age", "Int"
            t.field "name", "String"
            t.field "hair_color", "Color"
            t.warehouse_table "my_type"
          end
        end



        expect(config.warehouse_config["my_type"]).to include(
           "create_table_command" => "CREATE TABLE IF NOT EXISTS my_type (age  INT,\n  name  STRING,\n  hair_color  STRING);",
           "parquet_definition" => "message my_type {\nage  integer;\n  name  binary;\n  hair_color  ENUM;\n}\n",
        )
      end


      it "handles nested object types" do
        config = define_schema(
          schema_element_name_form: "snake_case")  do |s|
          s.object_type "Employer" do |t|
            t.field "name", "String"
          end

          s.object_type "Person" do |t|
            t.field "name", "String"
            t.field "employer", "Employer"
            t.warehouse_table "person"
          end
        end



        expect(config.warehouse_config["person"]).to include(
          "create_table_command" => "CREATE TABLE IF NOT EXISTS person (name  STRING,\n  employer  STRUCT<name  STRING>);",
          "parquet_definition" => "message person {\nname  binary;\n  optional group employer  {name  binary;};\n}\n",
        )
      end

      it "returns returns resaonable values for list fields" do

        config = define_schema(
          schema_element_name_form: "snake_case")  do |s|
          s.object_type "MyType" do |t|
            t.field "id", "ID"
            t.field "hobbies", "[String]"
            t.warehouse_table "my_type"
          end
        end



        expect(config.warehouse_config["my_type"]).to include(
           "create_table_command" => "CREATE TABLE IF NOT EXISTS my_type (id STRING,\n  hobbies ARRAY<STRING>);",
           "parquet_definition" => "message my_type {\nid  binary;\n  hobbies unknown;\n}\n",
        )
      end
    end
  end
end

