# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/spec_support/schema_definition_helpers"

module ElasticGraph
  module SchemaDefinition
    ::RSpec.describe "JSON schema field metadata generation" do
      include_context "SchemaDefinitionHelpers"

      it "generates no field metadata for built-in scalar and enum types" do
        metadata_by_type_and_field_name = dump_metadata

        json_schema_field_metadata = %w[
          Boolean Float ID Int String
          Cursor Date DateTime DistanceUnit JsonSafeLong LocalTime LongString TimeZone Untyped
        ].map do |type_name|
          metadata_by_type_and_field_name.fetch(type_name)
        end

        expect(json_schema_field_metadata).to all eq({})
      end

      it "generates field metadata for built-in object types" do
        metadata_by_field_name = dump_metadata.fetch("GeoLocation")

        expect(metadata_by_field_name).to eq({
          "latitude" => field_meta_of("Float!", "lat"),
          "longitude" => field_meta_of("Float!", "lon")
        })
      end

      it "generates field metadata for user-defined object types" do
        metadata_by_field_name = dump_metadata do |schema|
          schema.object_type "Money" do |t|
            t.field "amount", "Int"
            t.field "currency", "String"
          end
        end.fetch("Money")

        expect(metadata_by_field_name).to eq({
          "amount" => field_meta_of("Int", "amount"),
          "currency" => field_meta_of("String", "currency")
        })
      end

      it "respects the type and `name_in_index` on user-defined fields" do
        metadata_by_field_name = dump_metadata do |schema|
          schema.object_type "Money" do |t|
            t.field "amount", "Int!", name_in_index: "amount2"
            t.field "currency", "[String]!", name_in_index: "currency2"
          end
        end.fetch("Money")

        expect(metadata_by_field_name).to eq({
          "amount" => field_meta_of("Int!", "amount2"),
          "currency" => field_meta_of("[String]!", "currency2")
        })
      end

      it "generates no field metadata for user-defined scalar or enum types since they have no subfields" do
        metadata_by_type_and_field_name = dump_metadata do |schema|
          schema.scalar_type "Url" do |t|
            t.json_schema type: "string"
            t.mapping type: "keyword"
          end

          schema.enum_type "Color" do |t|
            t.value "RED"
            t.value "GREEN"
            t.value "BLUE"
          end
        end

        json_schema_field_metadata = %w[Url Color].map do |type_name|
          metadata_by_type_and_field_name.fetch(type_name)
        end

        expect(json_schema_field_metadata).to all eq({})
      end

      it "generates no field metadata for user-defined union or interface types since the JSON schema" do
        metadata_by_type_and_field_name = dump_metadata do |schema|
          schema.interface_type "Named" do |t|
            t.field "name", "String"
          end

          schema.union_type "Character" do |t|
            t.subtype "Droid"
            t.subtype "Human"
          end

          schema.object_type "Droid" do |t|
            t.implements "Named"
            t.field "name", "String"
            t.field "model", "String"
          end

          schema.object_type "Human" do |t|
            t.implements "Named"
            t.field "name", "String"
            t.field "home_planet", "String"
          end
        end

        json_schema_field_metadata = %w[Named Character].map do |type_name|
          metadata_by_type_and_field_name.fetch(type_name)
        end

        expect(json_schema_field_metadata).to all eq({})
      end

      it "includes the JSON schema field metadata in the versioned JSON schemas but not in the current public JSON schema" do
        results = define_schema do |schema|
          schema.object_type "Money" do |t|
            t.field "amount", "Int"
            t.field "currency", "String"
          end
        end

        amount_path = ["$defs", "Money", "properties", "amount"]

        expect(results.json_schemas_for(1).dig(*amount_path)).to eq({
          "anyOf" => [{"$ref" => "#/$defs/Int"}, {"type" => "null"}],
          "ElasticGraph" => {"nameInIndex" => "amount", "type" => "Int"}
        })

        expect(results.current_public_json_schema.dig(*amount_path)).to eq({
          "anyOf" => [{"$ref" => "#/$defs/Int"}, {"type" => "null"}]
        })
      end

      def dump_metadata(&schema_definition)
        define_schema(&schema_definition).json_schema_field_metadata_by_type_and_field_name
      end

      def define_schema(&schema_definition)
        super(schema_element_name_form: "snake_case", &schema_definition)
      end

      def field_meta_of(type, name_in_index)
        Indexing::JSONSchemaFieldMetadata.new(type: type, name_in_index: name_in_index)
      end
    end
  end
end
