# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/spec_support/schema_definition_helpers"

module ElasticGraph
  module SchemaDefinition
    module SchemaElements
      RSpec.describe DeprecatedElement do
        include_context "SchemaDefinitionHelpers"

        it "records `deleted_type`, `deleted_field`, and `renamed_from` calls so that extensions (such as ingestion serializers) can consume them" do
          state = define_schema(schema_element_name_form: "snake_case") do |schema|
            schema.deleted_type "OldType"

            schema.object_type "Widget" do |t|
              t.renamed_from "OldWidget"
              t.deleted_field "legacy_name"

              t.field "id", "ID!"
              t.field "name", "String" do |f|
                f.renamed_from "old_name"
              end
            end
          end.state

          expect(state.deleted_types_by_old_name.keys).to eq ["OldType"]
          expect(state.renamed_types_by_old_name.keys).to eq ["OldWidget"]
          expect(state.deleted_fields_by_type_name_and_old_field_name.fetch("Widget").keys).to eq ["legacy_name"]
          expect(state.renamed_fields_by_type_name_and_old_field_name.fetch("Widget").keys).to eq ["old_name"]

          expect(state.deleted_types_by_old_name.fetch("OldType").description).to match(
            /\A`schema\.deleted_type "OldType"` at .+:\d+\z/
          )
          expect(state.renamed_types_by_old_name.fetch("OldWidget").description).to match(
            /\A`type\.renamed_from "OldWidget"` at .+:\d+\z/
          )
          expect(state.deleted_fields_by_type_name_and_old_field_name.fetch("Widget").fetch("legacy_name").description).to match(
            /\A`type\.deleted_field "legacy_name"` at .+:\d+\z/
          )
          expect(state.renamed_fields_by_type_name_and_old_field_name.fetch("Widget").fetch("old_name").description).to match(
            /\A`field\.renamed_from "old_name"` at .+:\d+\z/
          )
        end

        it "reports the caller's schema definition location (not ElasticGraph internals) as `defined_at`" do
          deleted_type_callsite = nil
          renamed_type_callsite = nil
          deleted_field_callsite = nil
          renamed_field_callsite = nil

          state = define_schema(schema_element_name_form: "snake_case") do |schema|
            deleted_type_callsite = __LINE__ + 1
            schema.deleted_type "OldType"

            schema.object_type "Widget" do |t|
              renamed_type_callsite = __LINE__ + 1
              t.renamed_from "OldWidget"

              deleted_field_callsite = __LINE__ + 1
              t.deleted_field "legacy_name"

              t.field "id", "ID!"
              t.field "name", "String" do |f|
                renamed_field_callsite = __LINE__ + 1
                f.renamed_from "old_name"
              end
            end
          end.state

          expect(state.deleted_types_by_old_name.fetch("OldType").defined_at).to have_attributes(
            path: __FILE__,
            lineno: deleted_type_callsite
          )
          expect(state.renamed_types_by_old_name.fetch("OldWidget").defined_at).to have_attributes(
            path: __FILE__,
            lineno: renamed_type_callsite
          )
          expect(state.deleted_fields_by_type_name_and_old_field_name.fetch("Widget").fetch("legacy_name").defined_at).to have_attributes(
            path: __FILE__,
            lineno: deleted_field_callsite
          )
          expect(state.renamed_fields_by_type_name_and_old_field_name.fetch("Widget").fetch("old_name").defined_at).to have_attributes(
            path: __FILE__,
            lineno: renamed_field_callsite
          )
        end
      end
    end
  end
end
