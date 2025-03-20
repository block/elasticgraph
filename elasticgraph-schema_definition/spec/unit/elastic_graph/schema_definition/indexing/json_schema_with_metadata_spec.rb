# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/spec_support/schema_definition_helpers"
require "elastic_graph/schema_definition/indexing/json_schema_with_metadata"

module ElasticGraph
  module SchemaDefinition
    module Indexing
      ::RSpec.describe JSONSchemaWithMetadata do
        include_context "SchemaDefinitionHelpers"

        it "ignores derived indexed types that do not show up in the JSON schema" do
          v1_json_schema = dump_versioned_json_schema do |schema|
            schema.json_schema_version 1

            schema.object_type "Widget" do |t|
              t.field "amount", "Float"
              t.field "cost_currency", "String"
              t.field "cost_currency_name", "String"
              t.derive_indexed_type_fields "WidgetCurrency", from_id: "cost_currency" do |derive|
                derive.immutable_value "name", from: "cost_currency_name"
              end
            end

            schema.object_type "WidgetCurrency" do |t|
              t.field "id", "ID!"
              t.field "name", "String"
              t.index "widget_currencies"
            end
          end

          expect(v1_json_schema.fetch("$defs").keys).to include("Widget").and exclude("WidgetCurrency")
        end

        context "when merged into an old versioned JSON schema" do
          it "maintains the same metadata when a field has not changed" do
            v1_json_schema = dump_versioned_json_schema do |schema|
              schema.json_schema_version 1

              schema.object_type "Widget" do |t|
                t.field "amount", "Float"
              end
            end

            updated_v1_json_schema = dump_versioned_json_schema(v1_json_schema) do |schema|
              schema.json_schema_version 2

              schema.object_type "Widget" do |t|
                t.field "amount", "Float"
              end
            end

            expect(
              metadata_for(v1_json_schema, "Widget", "amount")
            ).to eq(metadata_for(updated_v1_json_schema, "Widget", "amount")).and have_dumped_metadata("amount", "Float")
          end

          it "does not record metadata on the `__typename` field since it has special handling in our indexing logic" do
            v1_json_schema = dump_versioned_json_schema do |schema|
              schema.json_schema_version 1

              schema.object_type "Widget" do |t|
                t.field "amount", "Float"
              end
            end

            updated_v1_json_schema = dump_versioned_json_schema(v1_json_schema) do |schema|
              schema.json_schema_version 2

              schema.object_type "Widget" do |t|
                t.field "amount", "Float"
              end
            end

            expect(
              v1_json_schema.dig("$defs", "Widget", "properties", "__typename").keys
            ).to eq(updated_v1_json_schema.dig("$defs", "Widget", "properties", "__typename").keys).and exclude("ElasticGraph")
          end

          it "records a changed field `type` so that the correct indexing preparer gets used when events at the old version are ingested" do
            v1_json_schema = dump_versioned_json_schema do |schema|
              schema.json_schema_version 1

              schema.object_type "Widget" do |t|
                t.field "amount", "Float"
              end
            end

            updated_v1_json_schema = dump_versioned_json_schema(v1_json_schema) do |schema|
              schema.json_schema_version 2

              schema.object_type "Widget" do |t|
                t.field "amount", "Int"
              end
            end

            expect(metadata_for(v1_json_schema, "Widget", "amount")).to have_dumped_metadata("amount", "Float")
            expect(metadata_for(updated_v1_json_schema, "Widget", "amount")).to have_dumped_metadata("amount", "Int")
          end

          it "records a changed field `name_in_index` so that the field gets written to the correct field in the index" do
            v1_json_schema = dump_versioned_json_schema do |schema|
              schema.json_schema_version 1

              schema.object_type "Widget" do |t|
                t.field "description", "String"
              end
            end

            updated_v1_json_schema = dump_versioned_json_schema(v1_json_schema) do |schema|
              schema.json_schema_version 2

              schema.object_type "Widget" do |t|
                t.field "description", "String", name_in_index: "description_text" do |f|
                  f.mapping type: "text"
                end
              end
            end

            expect(metadata_for(v1_json_schema, "Widget", "description")).to have_dumped_metadata("description", "String")
            expect(metadata_for(updated_v1_json_schema, "Widget", "description")).to have_dumped_metadata("description_text", "String")
          end

          it "notifies of an issue when a field has been deleted or renamed without recording what happened" do
            v1_json_schema = dump_versioned_json_schema do |schema|
              schema.json_schema_version 1

              schema.object_type "Widget" do |t|
                t.field "id", "ID"
                t.field "description", "String"
              end
            end

            missing_fields = dump_versioned_json_schema_missing_fields(v1_json_schema) do |schema|
              schema.json_schema_version 2

              schema.object_type "Widget" do |t|
                t.field "full_description", "String", name_in_index: "description"
              end
            end

            expect(missing_fields).to contain_exactly("Widget.description", "Widget.id")
          end

          it "supports renamed fields when `renamed_from` is used" do
            v1_json_schema = dump_versioned_json_schema do |schema|
              schema.json_schema_version 1

              schema.object_type "Widget" do |t|
                t.field "description", "String"
              end
            end

            updated_v1_json_schema = dump_versioned_json_schema(v1_json_schema) do |schema|
              schema.json_schema_version 2

              schema.object_type "Widget" do |t|
                t.field "full_description", "String!", name_in_index: "description" do |f|
                  f.renamed_from "description"
                end
              end
            end

            expect(metadata_for(v1_json_schema, "Widget", "description")).to have_dumped_metadata("description", "String")
            expect(metadata_for(updated_v1_json_schema, "Widget", "description")).to have_dumped_metadata("description", "String!")
          end

          it "supports deleted fields when `deleted_field` is used" do
            v1_json_schema = dump_versioned_json_schema do |schema|
              schema.json_schema_version 1

              schema.object_type "Widget" do |t|
                t.field "id", "ID"
                t.field "description", "String"
              end
            end

            updated_v1_json_schema = dump_versioned_json_schema(v1_json_schema) do |schema|
              schema.json_schema_version 2

              schema.object_type "Widget" do |t|
                t.field "id", "ID"
                t.deleted_field "description"
              end
            end

            expect(metadata_for(v1_json_schema, "Widget", "description")).to have_dumped_metadata("description", "String")
            expect(metadata_for(updated_v1_json_schema, "Widget", "description")).to eq nil
          end

          it "notifies of an issue when a type has been deleted or renamed without recording what happened" do
            v1_json_schema = dump_versioned_json_schema do |schema|
              schema.json_schema_version 1

              schema.object_type "Options" do |t|
                t.field "size", "Int"
              end

              schema.object_type "Widget" do |t|
                t.field "amount", "Float"
              end
            end

            missing_types = dump_versioned_json_schema_missing_types(v1_json_schema) do |schema|
              schema.json_schema_version 2

              # Widget has been renamed to `Component`.
              schema.object_type "Component" do |t|
                t.field "amount", "Float"
              end
            end

            expect(missing_types).to contain_exactly("Options", "Widget")
          end

          it "supports renamed types when `renamed_from` is used" do
            v1_json_schema = dump_versioned_json_schema do |schema|
              schema.json_schema_version 1

              schema.object_type "Widget" do |t|
                t.field "amount", "Float"
              end
            end

            updated_v1_json_schema = dump_versioned_json_schema(v1_json_schema) do |schema|
              schema.json_schema_version 2

              schema.object_type "Component" do |t|
                t.field "amount", "Int", name_in_index: "amount_int"
                t.renamed_from "Widget"
              end
            end

            expect(metadata_for(v1_json_schema, "Widget", "amount")).to have_dumped_metadata("amount", "Float")
            expect(metadata_for(updated_v1_json_schema, "Widget", "amount")).to have_dumped_metadata("amount_int", "Int")
          end

          it "supports deleted types when `deleted_type` is used" do
            v1_json_schema = dump_versioned_json_schema do |schema|
              schema.json_schema_version 1

              schema.object_type "Widget" do |t|
                t.field "amount", "Float"
              end
            end

            updated_v1_json_schema = dump_versioned_json_schema(v1_json_schema) do |schema|
              schema.json_schema_version 2

              schema.object_type "Component" do |t|
                t.field "id", "ID"
              end

              schema.deleted_type "Widget"
            end

            expect(metadata_for(v1_json_schema, "Widget", "amount")).to have_dumped_metadata("amount", "Float")
            expect(metadata_for(updated_v1_json_schema, "Widget", "amount")).to eq(nil)
          end

          it "supports deleted and renamed fields on a renamed type so long as these are indicated through `deleted_` and `renamed_` API calls" do
            v1_json_schema = dump_versioned_json_schema do |schema|
              schema.json_schema_version 1

              schema.object_type "Widget" do |t|
                t.field "token", "String"
                t.field "amount", "Float"
              end
            end

            updated_v1_json_schema = dump_versioned_json_schema(v1_json_schema) do |schema|
              schema.json_schema_version 2

              schema.object_type "Component" do |t|
                t.renamed_from "Widget"

                t.field "id", "ID" do |f|
                  f.renamed_from "token"
                end

                t.deleted_field "amount"
              end
            end

            expect(metadata_for(updated_v1_json_schema, "Widget", "token")).to have_dumped_metadata("id", "ID")
            expect(metadata_for(updated_v1_json_schema, "Widget", "amount")).to eq(nil)
          end

          it "keeps track of unused `deleted_field` calls" do
            v1_json_schema = dump_versioned_json_schema do |schema|
              schema.json_schema_version 1

              schema.object_type "Widget" do |t|
                t.field "token", "ID"
              end
            end

            unused_deprecated_elements = dump_versioned_json_schema_unused_deprecated_elements(v1_json_schema) do |schema|
              schema.json_schema_version 2

              schema.object_type "Widget" do |t|
                t.field "id", "ID"
                t.deleted_field "token" # used
                t.deleted_field "other" # unused
              end
            end

            expect(unused_deprecated_elements.map(&:description)).to eq [
              %(`type.deleted_field "other"` at #{__FILE__}:#{__LINE__ - 5})
            ]
          end

          it "keeps track of unused `renamed_field` calls" do
            v1_json_schema = dump_versioned_json_schema do |schema|
              schema.json_schema_version 1

              schema.object_type "Widget" do |t|
                t.field "token", "ID"
              end
            end

            unused_deprecated_elements = dump_versioned_json_schema_unused_deprecated_elements(v1_json_schema) do |schema|
              schema.json_schema_version 2

              schema.object_type "Widget" do |t|
                t.field "id", "ID" do |f|
                  f.renamed_from "token" # used
                  f.renamed_from "other" # unused
                end
              end
            end

            expect(unused_deprecated_elements.map(&:description)).to eq [
              %(`field.renamed_from "other"` at #{__FILE__}:#{__LINE__ - 6})
            ]
          end

          it "keeps track of unused `deleted_type` calls" do
            v1_json_schema = dump_versioned_json_schema do |schema|
              schema.json_schema_version 1

              schema.object_type "Widget" do |t|
                t.field "token", "ID"
              end
            end

            unused_deprecated_elements = dump_versioned_json_schema_unused_deprecated_elements(v1_json_schema) do |schema|
              schema.json_schema_version 2

              schema.deleted_type "Widget" # used
              schema.deleted_type "Other" # unused
            end

            expect(unused_deprecated_elements.map(&:description)).to eq [
              %(`schema.deleted_type "Other"` at #{__FILE__}:#{__LINE__ - 4})
            ]
          end

          it "keeps track of unused `renamed_type` calls" do
            v1_json_schema = dump_versioned_json_schema do |schema|
              schema.json_schema_version 1

              schema.object_type "Widget" do |t|
                t.field "token", "ID"
              end
            end

            unused_deprecated_elements = dump_versioned_json_schema_unused_deprecated_elements(v1_json_schema) do |schema|
              schema.json_schema_version 2

              schema.object_type "Component" do |t|
                t.field "token", "ID"
                t.renamed_from "Widget" # used
                t.renamed_from "Other" # unused
              end
            end

            expect(unused_deprecated_elements.map(&:description)).to eq [
              %(`type.renamed_from "Other"` at #{__FILE__}:#{__LINE__ - 5})
            ]
          end

          context "on a type that is using `route_with`" do
            it "does not allow a `route_with` field to be entirely missing from an old version of the schema" do
              v1_json_schema = dump_versioned_json_schema do |schema|
                schema.json_schema_version 1

                schema.object_type "Widget" do |t|
                  t.field "id", "ID"
                  t.field "workspace_id", "ID"

                  t.index "widgets" do |f|
                    f.route_with "workspace_id"
                  end
                end
              end

              missing_necessary_fields = dump_versioned_json_schema_missing_necessary_fields(v1_json_schema) do |schema|
                schema.json_schema_version 2

                schema.object_type "Widget" do |t|
                  t.field "id", "ID"
                  t.field "workspace_id2", "ID"
                  t.deleted_field "workspace_id"

                  t.index "widgets" do |f|
                    f.route_with "workspace_id2"
                  end
                end
              end

              expect(missing_necessary_fields).to eq [missing_necessary_field_of("routing", "Widget.workspace_id2")]
            end

            it "uses the `name_in_index` when determining if a `route_with` field is missing from an old version of the schema" do
              v1_json_schema = dump_versioned_json_schema do |schema|
                schema.json_schema_version 1

                schema.object_type "Widget" do |t|
                  t.field "id", "ID"
                  t.field "workspace_id", "ID"

                  t.index "widgets" do |f|
                    f.route_with "workspace_id"
                  end
                end
              end

              missing_necessary_fields = dump_versioned_json_schema_missing_necessary_fields(v1_json_schema) do |schema|
                schema.json_schema_version 2

                schema.object_type "Widget" do |t|
                  t.field "id", "ID"
                  t.field "workspace_id2", "ID", name_in_index: "workspace_id3"
                  t.deleted_field "workspace_id"

                  t.index "widgets" do |f|
                    f.route_with "workspace_id2"
                  end
                end
              end

              expect(missing_necessary_fields).to eq [missing_necessary_field_of("routing", "Widget.workspace_id3")]

              updated_v1_json_schema = dump_versioned_json_schema(v1_json_schema) do |schema|
                schema.json_schema_version 2

                schema.object_type "Widget" do |t|
                  t.field "id", "ID"
                  t.field "workspace_id2", "ID", name_in_index: "workspace_id" do |f|
                    f.renamed_from "workspace_id"
                  end

                  t.index "widgets" do |f|
                    f.route_with "workspace_id2"
                  end
                end
              end

              expect(metadata_for(updated_v1_json_schema, "Widget", "workspace_id")).to include("nameInIndex" => "workspace_id")
            end

            it "handles embedded fields when determining if a `route_with` field is missing from an old schema version" do
              v1_json_schema = dump_versioned_json_schema do |schema|
                schema.json_schema_version 1

                schema.object_type "Embedded" do |t|
                  t.field "workspace_id", "ID"
                end

                schema.object_type "Widget" do |t|
                  t.field "id", "ID"
                  t.field "embedded", "Embedded"

                  t.index "widgets" do |f|
                    f.route_with "embedded.workspace_id"
                  end
                end
              end

              missing_necessary_fields = dump_versioned_json_schema_missing_necessary_fields(v1_json_schema) do |schema|
                schema.json_schema_version 2

                schema.object_type "Embedded" do |t|
                  t.field "workspace_id", "ID"
                end

                schema.object_type "Widget" do |t|
                  t.field "id", "ID"
                  t.field "embedded2", "Embedded"
                  t.deleted_field "embedded"

                  t.index "widgets" do |f|
                    f.route_with "embedded2.workspace_id"
                  end
                end
              end

              expect(missing_necessary_fields).to eq [missing_necessary_field_of("routing", "Widget.embedded2.workspace_id")]

              updated_v1_json_schema = dump_versioned_json_schema(v1_json_schema) do |schema|
                schema.json_schema_version 2

                schema.object_type "Embedded" do |t|
                  t.field "workspace_id", "ID"
                end

                schema.object_type "Widget" do |t|
                  t.field "id", "ID"
                  t.field "embedded2", "Embedded" do |f|
                    f.renamed_from "embedded"
                  end

                  t.index "widgets" do |f|
                    f.route_with "embedded2.workspace_id"
                  end
                end
              end

              expect(metadata_for(updated_v1_json_schema, "Widget", "embedded")).to include("nameInIndex" => "embedded2")
            end

            it "handles renamed types" do
              v1_json_schema = dump_versioned_json_schema do |schema|
                schema.json_schema_version 1

                schema.object_type "Widget" do |t|
                  t.field "id", "ID"
                  t.field "workspace_id", "ID"

                  t.index "widgets" do |f|
                    f.route_with "workspace_id"
                  end
                end
              end

              updated_v1_json_schema = dump_versioned_json_schema(v1_json_schema) do |schema|
                schema.json_schema_version 2

                schema.object_type "Widget2" do |t|
                  t.field "id", "ID"
                  t.field "workspace_id", "ID"
                  t.renamed_from "Widget"

                  t.index "widgets" do |f|
                    f.route_with "workspace_id"
                  end
                end
              end

              expect(metadata_for(updated_v1_json_schema, "Widget", "workspace_id")).to include("nameInIndex" => "workspace_id")

              missing_necessary_fields = dump_versioned_json_schema_missing_necessary_fields(v1_json_schema) do |schema|
                schema.json_schema_version 2

                schema.object_type "Widget2" do |t|
                  t.field "id", "ID"
                  t.field "workspace_id2", "ID"
                  t.deleted_field "workspace_id"
                  t.renamed_from "Widget"

                  t.index "widgets" do |f|
                    f.route_with "workspace_id2"
                  end
                end
              end

              expect(missing_necessary_fields).to eq [missing_necessary_field_of("routing", "Widget2.workspace_id2")]
            end

            it "handles deleted types" do
              v1_json_schema = dump_versioned_json_schema do |schema|
                schema.json_schema_version 1

                schema.object_type "Widget" do |t|
                  t.field "id", "ID"
                  t.field "workspace_id", "ID"

                  t.index "widgets" do |f|
                    f.route_with "workspace_id"
                  end
                end
              end

              updated_v1_json_schema = dump_versioned_json_schema(v1_json_schema) do |schema|
                schema.json_schema_version 2

                schema.deleted_type "Widget"

                schema.object_type "Widget2" do |t|
                  t.field "id", "ID"
                  t.field "workspace_id", "ID"

                  t.index "widgets" do |f|
                    f.route_with "workspace_id"
                  end
                end
              end

              expect(metadata_for(updated_v1_json_schema, "Widget2", "workspace_id")).to eq nil
              expect(metadata_for(updated_v1_json_schema, "Widget", "workspace_id")).to eq nil
            end
          end

          context "on a type using `rollover`" do
            it "does not allow a `rollover` field to be entirely missing from an old version of the schema" do
              v1_json_schema = dump_versioned_json_schema do |schema|
                schema.json_schema_version 1

                schema.object_type "Widget" do |t|
                  t.field "id", "ID"
                  t.field "created_at", "DateTime"

                  t.index "widgets" do |f|
                    f.rollover :yearly, "created_at"
                  end
                end
              end

              missing_necessary_fields = dump_versioned_json_schema_missing_necessary_fields(v1_json_schema) do |schema|
                schema.json_schema_version 2

                schema.object_type "Widget" do |t|
                  t.field "id", "ID"
                  t.field "created_at2", "DateTime", name_in_index: "created_at3"
                  t.deleted_field "created_at"

                  t.index "widgets" do |f|
                    f.rollover :yearly, "created_at2"
                  end
                end
              end

              expect(missing_necessary_fields).to eq [missing_necessary_field_of("rollover", "Widget.created_at3")]

              updated_v1_json_schema = dump_versioned_json_schema(v1_json_schema) do |schema|
                schema.json_schema_version 2

                schema.object_type "Widget" do |t|
                  t.field "id", "ID"
                  t.field "created_at2", "DateTime", name_in_index: "created_at" do |f|
                    f.renamed_from "created_at"
                  end

                  t.index "widgets" do |f|
                    f.rollover :yearly, "created_at2"
                  end
                end
              end

              expect(metadata_for(updated_v1_json_schema, "Widget", "created_at")).to include("nameInIndex" => "created_at")
            end

            it "uses the `name_in_index` when determining if a `rollover` field is missing from an old version of the schema" do
              v1_json_schema = dump_versioned_json_schema do |schema|
                schema.json_schema_version 1

                schema.object_type "Widget" do |t|
                  t.field "id", "ID"
                  t.field "created_at", "DateTime"

                  t.index "widgets" do |f|
                    f.rollover :yearly, "created_at"
                  end
                end
              end

              missing_necessary_fields = dump_versioned_json_schema_missing_necessary_fields(v1_json_schema) do |schema|
                schema.json_schema_version 2

                schema.object_type "Widget" do |t|
                  t.field "id", "ID"
                  t.field "created_at2", "DateTime"
                  t.deleted_field "created_at"

                  t.index "widgets" do |f|
                    f.rollover :yearly, "created_at2"
                  end
                end
              end

              expect(missing_necessary_fields).to eq [missing_necessary_field_of("rollover", "Widget.created_at2")]
            end

            it "handles embedded fields when determining if a `rollover` field is missing from an old schema version" do
              v1_json_schema = dump_versioned_json_schema do |schema|
                schema.json_schema_version 1

                schema.object_type "Embedded" do |t|
                  t.field "created_at", "DateTime"
                end

                schema.object_type "Widget" do |t|
                  t.field "id", "ID"
                  t.field "embedded", "Embedded"

                  t.index "widgets" do |f|
                    f.rollover :yearly, "embedded.created_at"
                  end
                end
              end

              missing_necessary_fields = dump_versioned_json_schema_missing_necessary_fields(v1_json_schema) do |schema|
                schema.json_schema_version 2

                schema.object_type "Embedded" do |t|
                  t.field "created_at", "DateTime"
                end

                schema.object_type "Widget" do |t|
                  t.field "id", "ID"
                  t.field "embedded2", "Embedded"
                  t.deleted_field "embedded"

                  t.index "widgets" do |f|
                    f.rollover :yearly, "embedded2.created_at"
                  end
                end
              end

              expect(missing_necessary_fields).to eq [missing_necessary_field_of("rollover", "Widget.embedded2.created_at")]

              updated_v1_json_schema = dump_versioned_json_schema(v1_json_schema) do |schema|
                schema.json_schema_version 2

                schema.object_type "Embedded" do |t|
                  t.field "created_at", "DateTime"
                end

                schema.object_type "Widget" do |t|
                  t.field "id", "ID"
                  t.field "embedded2", "Embedded" do |f|
                    f.renamed_from "embedded"
                  end

                  t.index "widgets" do |f|
                    f.rollover :yearly, "embedded2.created_at"
                  end
                end
              end

              expect(metadata_for(updated_v1_json_schema, "Widget", "embedded")).to include("nameInIndex" => "embedded2")
            end

            it "handles renamed types" do
              v1_json_schema = dump_versioned_json_schema do |schema|
                schema.json_schema_version 1

                schema.object_type "Widget" do |t|
                  t.field "id", "ID"
                  t.field "created_at", "DateTime"

                  t.index "widgets" do |f|
                    f.rollover :yearly, "created_at"
                  end
                end
              end

              updated_v1_json_schema = dump_versioned_json_schema(v1_json_schema) do |schema|
                schema.json_schema_version 2

                schema.object_type "Widget2" do |t|
                  t.field "id", "ID"
                  t.field "created_at", "DateTime"
                  t.renamed_from "Widget"

                  t.index "widgets" do |f|
                    f.rollover :yearly, "created_at"
                  end
                end
              end

              expect(metadata_for(updated_v1_json_schema, "Widget", "created_at")).to include("nameInIndex" => "created_at")

              missing_necessary_fields = dump_versioned_json_schema_missing_necessary_fields(v1_json_schema) do |schema|
                schema.json_schema_version 2

                schema.object_type "Widget2" do |t|
                  t.field "id", "ID"
                  t.field "created_at2", "DateTime"
                  t.deleted_field "created_at"
                  t.renamed_from "Widget"

                  t.index "widgets" do |f|
                    f.rollover :yearly, "created_at2"
                  end
                end
              end

              expect(missing_necessary_fields).to eq [missing_necessary_field_of("rollover", "Widget2.created_at2")]
            end

            it "handles deleted types" do
              v1_json_schema = dump_versioned_json_schema do |schema|
                schema.json_schema_version 1

                schema.object_type "Widget" do |t|
                  t.field "id", "ID"
                  t.field "created_at", "DateTime"

                  t.index "widgets" do |f|
                    f.rollover :yearly, "created_at"
                  end
                end
              end

              updated_v1_json_schema = dump_versioned_json_schema(v1_json_schema) do |schema|
                schema.json_schema_version 2

                schema.deleted_type "Widget"

                schema.object_type "Widget2" do |t|
                  t.field "id", "ID"
                  t.field "created_at", "DateTime"

                  t.index "widgets" do |f|
                    f.rollover :yearly, "created_at"
                  end
                end
              end

              expect(metadata_for(updated_v1_json_schema, "Widget2", "created_at")).to eq nil
              expect(metadata_for(updated_v1_json_schema, "Widget", "created_at")).to eq nil
            end
          end

          describe "conflicting definition tracking" do
            it "includes a type that exists and is referenced from `deleted_type`" do
              elements = dump_versioned_json_schema_definition_conflicts do |schema|
                schema.object_type "Widget" do |t|
                  t.field "id", "ID"
                end

                schema.deleted_type "Widget"
              end

              expect(elements.map(&:description)).to contain_exactly(
                %(`schema.deleted_type "Widget"` at #{__FILE__}:#{__LINE__ - 4})
              )
            end

            it "includes a type that exists and is referenced from `renamed_from`" do
              elements = dump_versioned_json_schema_definition_conflicts do |schema|
                schema.object_type "Widget" do |t|
                  t.field "id", "ID"
                end

                schema.object_type "Component" do |t|
                  t.field "id", "ID"
                  t.renamed_from "Widget"
                end
              end

              expect(elements.map(&:description)).to contain_exactly(
                %(`type.renamed_from "Widget"` at #{__FILE__}:#{__LINE__ - 5})
              )
            end

            it "includes a type that exists and is referenced from `deleted_type` and `renamed_from`" do
              elements = dump_versioned_json_schema_definition_conflicts do |schema|
                schema.object_type "Widget" do |t|
                  t.field "id", "ID"
                end

                schema.object_type "Component" do |t|
                  t.field "id", "ID"
                  t.renamed_from "Widget"
                end

                schema.deleted_type "Widget"
              end

              expect(elements.map(&:description)).to contain_exactly(
                %(`type.renamed_from "Widget"` at #{__FILE__}:#{__LINE__ - 7}),
                %(`schema.deleted_type "Widget"` at #{__FILE__}:#{__LINE__ - 5})
              )
            end

            it "includes a type that is referenced from `deleted_type` and `renamed_from` but does not exist" do
              v1_json_schema = dump_versioned_json_schema do |schema|
                schema.json_schema_version 1

                schema.object_type "Widget" do |t|
                  t.field "token", "ID"
                end
              end

              elements = dump_versioned_json_schema_definition_conflicts(v1_json_schema) do |schema|
                schema.json_schema_version 2

                schema.object_type "Component" do |t|
                  t.field "id", "ID"
                  t.renamed_from "Widget"
                end

                schema.deleted_type "Widget"
              end

              expect(elements.map(&:description)).to contain_exactly(
                %(`type.renamed_from "Widget"` at #{__FILE__}:#{__LINE__ - 7}),
                %(`schema.deleted_type "Widget"` at #{__FILE__}:#{__LINE__ - 5})
              )
            end

            it "includes a field that exists and is referenced from `deleted_field`" do
              elements = dump_versioned_json_schema_definition_conflicts do |schema|
                schema.object_type "Widget" do |t|
                  t.field "id", "ID"
                  t.deleted_field "id"
                end
              end

              expect(elements.map(&:description)).to contain_exactly(
                %(`type.deleted_field "id"` at #{__FILE__}:#{__LINE__ - 5})
              )
            end

            it "includes a field that exists and is referenced from `renamed_from`" do
              elements = dump_versioned_json_schema_definition_conflicts do |schema|
                schema.object_type "Widget" do |t|
                  t.field "id", "ID"
                  t.field "token", "ID" do |f|
                    f.renamed_from "id"
                  end
                end
              end

              expect(elements.map(&:description)).to contain_exactly(
                %(`field.renamed_from "id"` at #{__FILE__}:#{__LINE__ - 6})
              )
            end

            it "includes a field that exists and is referenced from `deleted_field` and `renamed_from`" do
              elements = dump_versioned_json_schema_definition_conflicts do |schema|
                schema.object_type "Widget" do |t|
                  t.field "id", "ID"
                  t.field "token", "ID" do |f|
                    f.renamed_from "id"
                  end
                  t.deleted_field "id"
                end
              end

              expect(elements.map(&:description)).to contain_exactly(
                %(`type.deleted_field "id"` at #{__FILE__}:#{__LINE__ - 5}),
                %(`field.renamed_from "id"` at #{__FILE__}:#{__LINE__ - 8})
              )
            end

            it "includes a field that is referenced from `deleted_field` and `renamed_from` but does not exist" do
              v1_json_schema = dump_versioned_json_schema do |schema|
                schema.json_schema_version 1

                schema.object_type "Widget" do |t|
                  t.field "id", "ID"
                end
              end

              elements = dump_versioned_json_schema_definition_conflicts(v1_json_schema) do |schema|
                schema.json_schema_version 2

                schema.object_type "Widget" do |t|
                  t.field "token", "ID" do |f|
                    f.renamed_from "id"
                  end
                  t.deleted_field "id"
                end
              end

              expect(elements.map(&:description)).to contain_exactly(
                %(`type.deleted_field "id"` at #{__FILE__}:#{__LINE__ - 5}),
                %(`field.renamed_from "id"` at #{__FILE__}:#{__LINE__ - 8})
              )
            end
          end
        end

        def dump_versioned_json_schema(old_versioned_json_schema = nil, &schema_definition)
          merge_result = perform_merge(old_versioned_json_schema, &schema_definition)

          expect(merge_result.missing_fields).to be_empty
          expect(merge_result.missing_types).to be_empty
          expect(merge_result.definition_conflicts).to be_empty
          expect(merge_result.missing_necessary_fields).to be_empty

          merge_result.json_schema
        end

        def dump_versioned_json_schema_missing_fields(old_versioned_json_schema = nil, &schema_definition)
          merge_result = perform_merge(old_versioned_json_schema, &schema_definition)

          expect(merge_result.missing_fields).not_to be_empty
          expect(merge_result.missing_types).to be_empty
          expect(merge_result.definition_conflicts).to be_empty
          expect(merge_result.missing_necessary_fields).to be_empty

          merge_result.missing_fields
        end

        def dump_versioned_json_schema_definition_conflicts(old_versioned_json_schema = nil, &schema_definition)
          merge_result = perform_merge(old_versioned_json_schema, &schema_definition)

          expect(merge_result.missing_fields).to be_empty
          expect(merge_result.missing_types).to be_empty
          expect(merge_result.definition_conflicts).not_to be_empty
          expect(merge_result.missing_necessary_fields).to be_empty

          merge_result.definition_conflicts
        end

        def dump_versioned_json_schema_missing_types(old_versioned_json_schema = nil, &schema_definition)
          merge_result = perform_merge(old_versioned_json_schema, &schema_definition)

          expect(merge_result.missing_fields).to be_empty
          expect(merge_result.missing_types).not_to be_empty
          expect(merge_result.definition_conflicts).to be_empty
          expect(merge_result.missing_necessary_fields).to be_empty

          merge_result.missing_types
        end

        def dump_versioned_json_schema_missing_necessary_fields(old_versioned_json_schema = nil, &schema_definition)
          merge_result = perform_merge(old_versioned_json_schema, &schema_definition)

          expect(merge_result.missing_fields).to be_empty
          expect(merge_result.missing_types).to be_empty
          expect(merge_result.definition_conflicts).to be_empty
          expect(merge_result.missing_necessary_fields).not_to be_empty

          merge_result.missing_necessary_fields
        end

        def dump_versioned_json_schema_unused_deprecated_elements(old_versioned_json_schema = nil, &schema_definition)
          results = define_schema(&schema_definition)
          results.merge_field_metadata_into_json_schema(old_versioned_json_schema || results.current_public_json_schema)
          results.unused_deprecated_elements
        end

        def perform_merge(old_versioned_json_schema = nil, &schema_definition)
          results = define_schema(&schema_definition)
          results.merge_field_metadata_into_json_schema(old_versioned_json_schema || results.current_public_json_schema).tap do
            expect(results.unused_deprecated_elements).to be_empty
          end
        end

        def metadata_for(json_schema, type, field)
          json_schema.dig("$defs", type, "properties", field, "ElasticGraph")
        end

        def define_schema(&schema_definition)
          super(schema_element_name_form: "snake_case", &schema_definition)
        end

        def have_dumped_metadata(name_in_index, type)
          eq({"nameInIndex" => name_in_index, "type" => type})
        end

        def missing_necessary_field_of(field_type, fully_qualified_path)
          JSONSchemaWithMetadata::MissingNecessaryField.new(field_type, fully_qualified_path)
        end
      end
    end
  end
end
