# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/json_ingestion/schema_definition/indexing/field"
require "elastic_graph/json_ingestion/schema_definition/indexing/field_reference"
require "elastic_graph/json_ingestion/schema_definition/indexing/field_type/object"
require "elastic_graph/spec_support/schema_definition_helpers"

module ElasticGraph
  module JSONIngestion
    module SchemaDefinition
      module Indexing
        RSpec.describe "JSON schema indexing wrappers" do
          include_context "SchemaDefinitionHelpers"

          it "compares field references using both the wrapped reference and JSON schema options" do
            reference = widget_schema_field("name").to_indexing_field_reference
            matching_reference = FieldReference.new(
              reference.__getobj__,
              json_schema_layers: reference.json_schema_layers,
              json_schema_customizations: reference.json_schema_customizations,
              doc_comment: reference.doc_comment
            )
            different_reference = FieldReference.new(
              reference.__getobj__,
              json_schema_layers: reference.json_schema_layers,
              json_schema_customizations: {maxLength: 10},
              doc_comment: reference.doc_comment
            )
            different_doc_reference = FieldReference.new(
              reference.__getobj__,
              json_schema_layers: reference.json_schema_layers,
              json_schema_customizations: reference.json_schema_customizations,
              doc_comment: "alternate docs"
            )

            expect(reference).to eq(matching_reference)
            expect(reference.eql?(matching_reference)).to eq(true)
            expect(reference.hash).to eq(matching_reference.hash)
            expect(reference).not_to eq(different_reference)
            expect(reference).not_to eq(different_doc_reference)
            expect(reference == reference.__getobj__).to eq(true)
          end

          it "returns nil when resolving a field reference whose type is unresolved" do
            reference = FieldReference.new(
              ::ElasticGraph::SchemaDefinition::Indexing::FieldReference.new(
                name: "missing_type",
                name_in_index: "missing_type",
                type: unresolved_type_ref,
                mapping_options: {},
                accuracy_confidence: nil,
                source: nil,
                runtime_field_script: nil
              ),
              json_schema_layers: [],
              json_schema_customizations: {},
              doc_comment: nil
            )

            expect(reference.resolve).to eq(nil)
          end

          it "compares fields using both the wrapped field and JSON schema options" do
            field = widget_indexing_field("name")
            matching_field = Field.new(
              field.__getobj__,
              json_schema_layers: field.json_schema_layers,
              json_schema_customizations: field.json_schema_customizations,
              doc_comment: field.doc_comment
            )
            different_field = Field.new(
              field.__getobj__,
              json_schema_layers: field.json_schema_layers,
              json_schema_customizations: {maxLength: 10},
              doc_comment: field.doc_comment
            )
            different_doc_field = Field.new(
              field.__getobj__,
              json_schema_layers: field.json_schema_layers,
              json_schema_customizations: field.json_schema_customizations,
              doc_comment: "alternate docs"
            )

            expect(field).to eq(matching_field)
            expect(field.eql?(matching_field)).to eq(true)
            expect(field.hash).to eq(matching_field.hash)
            expect(field).not_to eq(different_field)
            expect(field).not_to eq(different_doc_field)
            expect(field == field.__getobj__).to eq(true)
          end

          it "compares object field types using both the wrapped field type and JSON schema options" do
            object_field_type = widget_field_type
            matching_object_field_type = FieldType::Object.new(object_field_type.__getobj__).tap do |field_type|
              field_type.json_schema_options = object_field_type.json_schema_options
            end
            different_object_field_type = FieldType::Object.new(object_field_type.__getobj__).tap do |field_type|
              field_type.json_schema_options = {type: "object"}
            end
            different_doc_object_field_type = FieldType::Object.new(object_field_type.__getobj__).tap do |field_type|
              field_type.json_schema_options = object_field_type.json_schema_options
              field_type.doc_comment = "alternate docs"
            end

            expect(object_field_type).to eq(matching_object_field_type)
            expect(object_field_type.eql?(matching_object_field_type)).to eq(true)
            expect(object_field_type.hash).to eq(matching_object_field_type.hash)
            expect(object_field_type).not_to eq(different_object_field_type)
            expect(object_field_type).not_to eq(different_doc_object_field_type)
            expect(object_field_type == object_field_type.__getobj__).to eq(true)
          end

          def widget_schema_field(name)
            widget_type.indexing_fields_by_name_in_index.fetch(name)
          end

          def widget_indexing_field(name)
            widget_field_type.subfields.find { |field| field.name == name }
          end

          def widget_field_type
            widget_type.to_indexing_field_type
          end

          def widget_type
            define_schema(schema_element_name_form: "snake_case") do |schema|
              schema.object_type "Widget" do |type|
                type.field "id", "ID!"
                type.field "name", "String" do |field|
                  field.json_schema minLength: 1
                end
              end
            end.state.object_types_by_name.fetch("Widget")
          end

          # A minimal stand-in for a `SchemaElements::TypeReference` that never resolves. References to
          # not-yet-defined types resolve to `nil` mid-definition; a stand-in lets us exercise that path
          # directly instead of relying on the timing of a partially-defined schema.
          def unresolved_type_ref
            Class.new do
              def fully_unwrapped
                self
              end

              def resolved
                nil
              end
            end.new
          end
        end
      end
    end
  end
end
