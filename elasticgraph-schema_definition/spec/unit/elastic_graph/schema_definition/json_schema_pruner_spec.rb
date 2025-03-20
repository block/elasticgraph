# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/constants"
require "elastic_graph/spec_support/schema_definition_helpers"
require "elastic_graph/schema_definition/json_schema_pruner"

module ElasticGraph
  module SchemaDefinition
    RSpec.describe JSONSchemaPruner do
      include_context "SchemaDefinitionHelpers"

      describe ".prune" do
        subject { described_class.prune(schema) }

        shared_examples "prunes types not referenced by indexed types" do |expected_type_names|
          it do
            expect(subject["$defs"].keys).to match_array(expected_type_names)
          end
        end

        context "when there are indexable types" do
          let(:schema) do
            dump_schema do |s|
              # Widget and Boolean should be present
              s.object_type "Widget" do |t|
                t.field "id", "ID!"
                t.field "inStock", "Boolean"
                t.index "widgets"
              end

              # UnindexedWidget and Float should get pruned
              s.object_type "UnindexedWidget" do |t|
                t.field "id", "ID!"
                t.field "cost", "Float"
              end
            end
          end

          it_behaves_like "prunes types not referenced by indexed types",
            [EVENT_ENVELOPE_JSON_SCHEMA_NAME, "Boolean", "ID", "Widget"]
        end

        context "when there are no types defined" do
          let(:schema) { dump_schema }

          it_behaves_like "prunes types not referenced by indexed types", [EVENT_ENVELOPE_JSON_SCHEMA_NAME]
        end

        context "when there are no indexable types defined" do
          let(:schema) do
            dump_schema do |s|
              # UnindexedWidget and Float should get pruned
              s.object_type "UnindexedWidget" do |t|
                t.field "id", "ID!"
                t.field "cost", "Float"
              end
            end
          end

          it_behaves_like "prunes types not referenced by indexed types", [EVENT_ENVELOPE_JSON_SCHEMA_NAME]
        end

        context "when there are nested types referenced from an indexed type" do
          let(:schema) do
            dump_schema do |s|
              s.object_type "Widget" do |t|
                t.field "id", "ID!"
                t.field "options", "WidgetOptions"
                t.index "widgets"
              end

              s.object_type "WidgetOptions" do |t|
                t.field "size", "Size"
                t.field "color", "Color"
                t.field "cost", "Money"
              end

              s.enum_type "Size" do |t|
                t.value "SMALL"
                t.value "MEDIUM"
                t.value "LARGE"
              end

              s.enum_type "Color" do |t|
                t.value "RED"
                t.value "YELLOW"
                t.value "BLUE"
              end

              s.object_type "Money" do |t|
                t.field "currency", "Currency"
                t.field "amount_cents", "Int"
              end

              s.enum_type "Currency" do |t|
                t.value "USD"
                t.value "CAD"
              end
            end
          end

          it_behaves_like "prunes types not referenced by indexed types", [
            EVENT_ENVELOPE_JSON_SCHEMA_NAME,
            "Color",
            "Currency",
            "ID",
            "Int",
            "Money",
            "Size",
            "Widget",
            "WidgetOptions"
          ]
        end
      end

      def dump_schema(&schema_definition)
        schema_definition_results = define_schema(schema_element_name_form: "snake_case", &schema_definition)
        latest_json_schema_version = schema_definition_results.latest_json_schema_version

        schema_definition_results.json_schemas_for(latest_json_schema_version)
      end
    end
  end
end
