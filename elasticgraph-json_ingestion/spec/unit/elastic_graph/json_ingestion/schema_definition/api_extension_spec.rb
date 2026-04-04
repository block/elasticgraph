# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/json_ingestion/schema_definition/api_extension"

module ElasticGraph
  module JSONIngestion
    module SchemaDefinition
      RSpec.describe APIExtension do
        def build_api_with_extension
          state = ::Data.define(:ingestion_serializer_state).new(ingestion_serializer_state: {})

          factory = ::Object.new

          api = ::Object.new
          api.instance_variable_set(:@state, state)
          api.define_singleton_method(:factory) { factory }
          api.extend(APIExtension)

          [api, state, factory]
        end

        it "extends the api factory with JSON schema factory behavior" do
          _api, _state, factory = build_api_with_extension

          expect(factory).to be_a(FactoryExtension)
        end

        it "initializes the JSON schema strictness defaults" do
          _api, state, = build_api_with_extension

          expect(state.ingestion_serializer_state[:allow_omitted_json_schema_fields]).to eq(false)
          expect(state.ingestion_serializer_state[:allow_extra_json_schema_fields]).to eq(true)
        end

        it "preserves existing JSON schema strictness settings when extended" do
          state = ::Data.define(:ingestion_serializer_state).new(
            ingestion_serializer_state: {
              allow_omitted_json_schema_fields: true,
              allow_extra_json_schema_fields: false
            }
          )

          factory = ::Object.new

          api = ::Object.new
          api.instance_variable_set(:@state, state)
          api.define_singleton_method(:factory) { factory }
          api.extend(APIExtension)

          expect(state.ingestion_serializer_state[:allow_omitted_json_schema_fields]).to eq(true)
          expect(state.ingestion_serializer_state[:allow_extra_json_schema_fields]).to eq(false)
        end

        it "merges reserved type names when composed with another ingestion serializer extension" do
          state = ::Data.define(:ingestion_serializer_state).new(
            ingestion_serializer_state: {
              reserved_type_names: Set["ReservedName"]
            }
          )

          factory = ::Object.new

          api = ::Object.new
          api.instance_variable_set(:@state, state)
          api.define_singleton_method(:factory) { factory }
          api.extend(APIExtension)

          expect(state.ingestion_serializer_state[:reserved_type_names]).to eq(
            Set["ReservedName", EVENT_ENVELOPE_JSON_SCHEMA_NAME]
          )
        end

        it "stores the JSON schema version and its setter location" do
          api, state, = build_api_with_extension

          expect(api.json_schema_version(3)).to eq(nil)
          expect(state.ingestion_serializer_state[:json_schema_version]).to eq(3)
          expect(state.ingestion_serializer_state[:json_schema_version_setter_location]).to be_a(::Thread::Backtrace::Location)
        end

        it "rejects invalid JSON schema versions" do
          api, = build_api_with_extension

          expect {
            api.json_schema_version(0)
          }.to raise_error(Errors::SchemaError, /must be a positive integer/)

          expect {
            api.json_schema_version("3")
          }.to raise_error(Errors::SchemaError, /must be a positive integer/)
        end

        it "rejects setting the JSON schema version more than once" do
          api, = build_api_with_extension
          api.json_schema_version(1)

          expect {
            api.json_schema_version(2)
          }.to raise_error(Errors::SchemaError, /can only be set once/)
        end

        it "stores JSON schema strictness settings" do
          api, state, = build_api_with_extension

          expect(api.json_schema_strictness(allow_omitted_fields: true, allow_extra_fields: false)).to eq(nil)
          expect(state.ingestion_serializer_state[:allow_omitted_json_schema_fields]).to eq(true)
          expect(state.ingestion_serializer_state[:allow_extra_json_schema_fields]).to eq(false)
        end

        it "validates JSON schema strictness arguments" do
          api, = build_api_with_extension

          expect {
            api.json_schema_strictness(allow_omitted_fields: :sometimes)
          }.to raise_error(Errors::SchemaError, /allow_omitted_fields/)

          expect {
            api.json_schema_strictness(allow_extra_fields: :sometimes)
          }.to raise_error(Errors::SchemaError, /allow_extra_fields/)
        end
      end

      RSpec.describe APIExtension, :json_ingestion_schema do
        it "adds JSON schema generation and artifact dumping through schema definition extension hooks" do
          results = define_json_ingestion_schema(reload_schema_artifacts: true, json_schema_version: nil) do |schema|
            schema.json_schema_version 2
            schema.json_schema_strictness allow_omitted_fields: true, allow_extra_fields: false

            schema.object_type "Widget" do |type|
              type.field "id", "ID!"
              type.field "name", "String"
              type.index "widgets"
            end
          end

          expect(results.available_json_schema_versions.to_a).to eq([2])
          expect(results.latest_json_schema_version).to eq(2)

          json_schema = results.json_schemas_for(2)

          expect(json_schema.fetch(JSON_SCHEMA_VERSION_KEY)).to eq(2)
          expect(json_schema.fetch("$defs")).to include("ElasticGraphEventEnvelope")
          expect(json_schema.dig("$defs", "Widget", "required")).to include("id")
        end

        it "exposes the JSON schema version setter location on schema results" do
          results = define_json_ingestion_schema(json_schema_version: nil) do |schema|
            schema.json_schema_version 2

            schema.object_type "Widget" do |type|
              type.field "id", "ID!"
              type.index "widgets"
            end
          end

          expect(results.json_schema_version_setter_location).to be_a(::Thread::Backtrace::Location)
        end

        it "rejects user-defined scalar types without a JSON schema definition" do
          expect {
            define_json_ingestion_schema(json_schema_version: nil) do |schema|
              schema.json_schema_version 2

              schema.scalar_type "Url" do |type|
                type.mapping type: "keyword"
              end
            end
          }.to raise_error(Errors::SchemaError, /Scalar types require `json_schema` to be configured, but `Url` lacks `json_schema`/)
        end

        it "supports enums whose input and output names are the same" do
          results = define_json_ingestion_schema(
            derived_type_name_formats: {InputEnum: "%{base}"},
            json_schema_version: nil
          ) do |schema|
            schema.json_schema_version 2

            schema.enum_type "Color" do |type|
              type.values "RED", "BLUE"
            end

            schema.object_type "Widget" do |type|
              type.field "id", "ID!"
              type.field "color", "Color!"
              type.index "widgets"
            end
          end

          expect(results.graphql_schema_string.scan(/^enum Color\b/)).to eq(["enum Color"])
          expect(results.json_schemas_for(2).dig("$defs", "Color")).to eq({
            "type" => "string",
            "enum" => %w[RED BLUE]
          })
        end
      end
    end
  end
end
