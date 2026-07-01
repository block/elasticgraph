# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  module JSONIngestion
    module SchemaDefinition
      RSpec.describe DeprecatedElement do
        it "records `deleted_type`, `deleted_field`, and `renamed_from` calls so that schema artifact tooling can consume them" do
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

          json_ingestion_state = state.json_ingestion_state

          expect(json_ingestion_state.deleted_types_by_old_name.keys).to eq ["OldType"]
          expect(json_ingestion_state.renamed_types_by_old_name.keys).to eq ["OldWidget"]
          expect(json_ingestion_state.deleted_fields_by_type_name_and_old_field_name.fetch("Widget").keys).to eq ["legacy_name"]
          expect(json_ingestion_state.renamed_fields_by_type_name_and_old_field_name.fetch("Widget").keys).to eq ["old_name"]

          expect(json_ingestion_state.deleted_types_by_old_name.fetch("OldType").description).to match(
            /\A`schema\.deleted_type "OldType"` at .+:\d+\z/
          )
          expect(json_ingestion_state.renamed_types_by_old_name.fetch("OldWidget").description).to match(
            /\A`type\.renamed_from "OldWidget"` at .+:\d+\z/
          )
          expect(json_ingestion_state.deleted_fields_by_type_name_and_old_field_name.fetch("Widget").fetch("legacy_name").description).to match(
            /\A`type\.deleted_field "legacy_name"` at .+:\d+\z/
          )
          expect(json_ingestion_state.renamed_fields_by_type_name_and_old_field_name.fetch("Widget").fetch("old_name").description).to match(
            /\A`field\.renamed_from "old_name"` at .+:\d+\z/
          )
        end
      end
    end
  end
end
