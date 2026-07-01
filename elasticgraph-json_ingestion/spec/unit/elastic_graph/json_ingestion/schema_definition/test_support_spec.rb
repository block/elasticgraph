# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/errors"

module ElasticGraph
  module JSONIngestion
    module SchemaDefinition
      # Verifies the JSON-ingestion `TestSupport` behavior that supplements the base
      # `ElasticGraph::SchemaDefinition::TestSupport`: injecting `APIExtension` and defaulting
      # the JSON schema version so specs don't have to set it explicitly.
      RSpec.describe "JSON ingestion TestSupport" do
        it "defaults the JSON schema version to 1 so specs need not set it" do
          results = define_schema(schema_element_name_form: "snake_case") do |schema|
            schema.object_type "Widget" do |t|
              t.field "id", "ID!"
              t.index "widgets"
            end
          end

          expect(results.available_json_schema_versions).to contain_exactly(1)
        end

        it "uses an explicitly-provided `json_schema_version`" do
          results = define_schema(schema_element_name_form: "snake_case", json_schema_version: 5) do |schema|
            schema.object_type "Widget" do |t|
              t.field "id", "ID!"
              t.index "widgets"
            end
          end

          expect(results.available_json_schema_versions).to contain_exactly(5)
        end

        it "leaves the version unset when `json_schema_version: nil`, so accessing it fails" do
          results = define_schema(schema_element_name_form: "snake_case", json_schema_version: nil) do |schema|
            schema.object_type "Widget" do |t|
              t.field "id", "ID!"
              t.index "widgets"
            end
          end

          expect {
            results.available_json_schema_versions
          }.to raise_error(Errors::SchemaError, a_string_including("must be specified in the schema"))
        end

        it "does not clobber a version the caller sets in the block" do
          results = define_schema(schema_element_name_form: "snake_case") do |schema|
            schema.json_schema_version 7

            schema.object_type "Widget" do |t|
              t.field "id", "ID!"
              t.index "widgets"
            end
          end

          expect(results.available_json_schema_versions).to contain_exactly(7)
        end

        it "injects `APIExtension` even when the caller passes other `extension_modules`" do
          other_extension = Module.new do
            def self.extended(api)
              api.state.reserved_type_names << "ReservedByOtherExtension"
            end
          end

          results = define_schema(schema_element_name_form: "snake_case", extension_modules: [other_extension]) do |schema|
            # `json_schema_version` is only available when `APIExtension` was injected.
            schema.json_schema_version 1

            schema.object_type "Widget" do |t|
              t.field "id", "ID!"
              t.index "widgets"
            end
          end

          expect(results.available_json_schema_versions).to contain_exactly(1)
        end

        describe "#generate_schema_artifacts" do
          it "defaults the JSON schema version to 1 so specs need not set it" do
            artifacts = generate_schema_artifacts do |schema|
              schema.object_type "Widget" do |t|
                t.field "id", "ID!"
                t.index "widgets"
              end
            end

            expect(artifacts.available_json_schema_versions).to contain_exactly(1)
          end

          it "does not clobber a version the block sets itself" do
            artifacts = generate_schema_artifacts do |schema|
              schema.json_schema_version 7

              schema.object_type "Widget" do |t|
                t.field "id", "ID!"
                t.index "widgets"
              end
            end

            expect(artifacts.available_json_schema_versions).to contain_exactly(7)
          end
        end
      end
    end
  end
end
